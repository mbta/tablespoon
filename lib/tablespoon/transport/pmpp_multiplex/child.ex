defmodule Tablespoon.Transport.PMPPMultiplex.Child do
  @moduledoc """
  GenServer responsible for maintaining a single connection and multiplexing messages.
  """
  use GenServer, restart: :temporary
  alias Tablespoon.Protocol.PMPP
  alias Tablespoon.Transport
  require Logger

  defstruct [:transport, :address, :id_fn, buffer: "", in_flight: %{}]

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
      {:ok, %__MODULE__{transport: transport, address: parent.address, id_fn: id_fn}}
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

        case Enum.reduce(messages, state, &handle_message/2) do
          %{} = state ->
            {:noreply, state}

          other ->
            other
        end

      :unknown ->
        _ =
          Logger.warn(fn ->
            "unexpected PMPPMultiplex.Child message pid=#{self()} message=#{inspect(message)}"
          end)

        {:noreply, state}
    end
  end

  defp do_send(key, iodata, state) do
    %{transport: transport, id_fn: id_fn, in_flight: in_flight} = state
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

  defp handle_message({:data, data}, state) do
    buffer = state.buffer <> data

    case PMPP.decode(buffer) do
      {:ok, pmpp, rest} ->
        state = %{state | buffer: rest}
        handle_pmpp(pmpp, state)

      {:error, :too_short, rest} ->
        %{state | buffer: rest}
    end
  end

  defp handle_message(:closed, state) do
    {:stop, :normal, state}
  end

  def handle_pmpp(pmpp, state) do
    with {:ok, request_id} <- state.id_fn.(pmpp.body),
         {{pid, ref}, in_flight} <- Map.pop(state.in_flight, request_id) do
      Kernel.send(pid, {ref, {:data, pmpp.body}})
      %{state | in_flight: in_flight}
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
