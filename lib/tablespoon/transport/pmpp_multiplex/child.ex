defmodule Tablespoon.Transport.PMPPMultiplex.Child do
  @moduledoc """
  GenServer responsible for maintaining a single connection and multiplexing messages.
  """
  use GenServer, restart: :temporary
  alias Tablespoon.Protocol.PMPP
  alias Tablespoon.Transport
  require Logger

  defstruct [:transport, :address, :id_fn, :max_in_flight, buffer: "", in_flight: %{}]

  def start_link({parent, name}) do
    GenServer.start_link(__MODULE__, parent, name: name)
  end

  def send({pid, ref}, iodata) do
    GenServer.call(pid, {:send, {self(), ref}, iodata})
  end

  @impl GenServer
  def init(parent) do
    with {:ok, transport} <- Transport.connect(parent.transport) do
      {m, f, a} = parent.id_mfa
      id_fn = &apply(m, f, [&1 | a])

      _ =
        Logger.info(fn ->
          "started PMPPMultiplex.Child pid=#{inspect(self())} parent=#{inspect(parent)}"
        end)

      {:ok,
       %__MODULE__{
         transport: transport,
         address: parent.address,
         max_in_flight: parent.max_in_flight,
         id_fn: id_fn
       }}
    end
  end

  @impl GenServer
  def handle_call({:send, key, iodata}, _from, state) do
    case do_send(key, iodata, state) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, _} = e ->
        {:reply, e, state}
    end
  end

  @impl GenServer
  def handle_info(message, state) do
    %{transport: transport} = state

    case Transport.stream(transport, message) do
      {:ok, transport, messages} ->
        state = %{state | transport: transport}

        Enum.reduce(messages, state, &handle_message/2)

      :unknown ->
        _ =
          Logger.warn(fn ->
            "unexpected PMPPMultiplex.Child message pid=#{inspect(self())} message=#{
              inspect(message)
            }"
          end)

        {:noreply, state}
    end
  end

  defp do_send(key, iodata, %{in_flight: in_flight, max_in_flight: max_in_flight} = state)
       when max_in_flight > map_size(in_flight) do
    %{transport: transport, id_fn: id_fn} = state
    binary = IO.iodata_to_binary(iodata)

    with {:ok, request_id} <- id_fn.(binary),
         encoded =
           PMPP.encode(%PMPP{address: state.address, control: :information_poll, body: binary}),
         {:ok, transport} <- Transport.send(transport, encoded) do
      in_flight = Map.put(in_flight, request_id, key)
      state = %{state | transport: transport, in_flight: in_flight}
      {:ok, state}
    end
  end

  defp do_send(_key, _iodata, _state) do
    {:error, :too_many_in_flight}
  end

  defp handle_message({:data, data}, state) do
    handle_buffer(%{state | buffer: state.buffer <> data})
  end

  defp handle_message(:closed, state) do
    {:stop, :normal, state}
  end

  defp handle_buffer(%{buffer: buffer} = state) when byte_size(buffer) > 0 do
    case PMPP.decode(buffer) do
      {:ok, pmpp, rest} ->
        state = %{state | buffer: rest}
        handle_pmpp(pmpp, state)

      {:error, :too_short, rest} ->
        {:noreply, %{state | buffer: rest}}
    end
  end

  defp handle_buffer(state) do
    {:noreply, state}
  end

  def handle_pmpp(pmpp, state) do
    with {:ok, request_id} <- state.id_fn.(pmpp.body),
         {{pid, ref}, in_flight} <- Map.pop(state.in_flight, request_id) do
      Kernel.send(pid, {ref, {:data, pmpp.body}})
      handle_buffer(%{state | in_flight: in_flight})
    else
      error ->
        _ =
          Logger.warn(fn ->
            "unable to match incoming PMPP message pmpp=#{inspect(pmpp, limit: :infinity)} in_flight=#{
              inspect(state.in_flight)
            } error=#{inspect(error)}"
          end)

        {:stop, :normal, state}
    end
  end
end
