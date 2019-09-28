defmodule Tablespoon.Transport.PMPPMultiplex.Child do
  @moduledoc """
  GenServer responsible for maintaining a single connection and multiplexing messages.
  """
  use GenServer
  alias Tablespoon.Protocol.PMPP
  alias Tablespoon.Transport
  require Logger

  defstruct [:transport, :address, :id_fn, buffer: "", in_flight: %{}]

  def start_link({transport, address, id_fn, name}) do
    GenServer.start_link(__MODULE__, {transport, address, id_fn}, name: name)
  end

  def send({pid, ref}, iodata) do
    GenServer.call(pid, {:send, {self(), ref}, iodata})
  end

  @impl GenServer
  def init({transport, address, id_fn}) do
    with {:ok, transport} <- Transport.connect(transport) do
      {:ok, %__MODULE__{transport: transport, address: address, id_fn: id_fn}}
    end
  end

  @impl GenServer
  def handle_call({:send, key, iodata}, _from, state) do
    %{transport: transport, id_fn: id_fn, in_flight: in_flight} = state
    {:ok, request_id} = id_fn.(iodata)
    encoded = PMPP.encode(%PMPP{address: state.address, control: :information_poll, body: iodata})
    {:ok, transport} = Transport.send(transport, encoded)
    in_flight = Map.put(in_flight, request_id, key)
    state = %{state | transport: transport, in_flight: in_flight}
    {:reply, :ok, state}
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

  def handle_pmpp(pmpp, state) do
    with {:ok, request_id} <- state.id_fn.(pmpp.body),
         {{pid, ref}, in_flight} <- Map.pop(state.in_flight, request_id) do
      Kernel.send(pid, {ref, {:data, pmpp.body}})
      %{state | in_flight: in_flight}
    else
      _ ->
        _ =
          Logger.warn(fn ->
            "unable to match incoming PMPP message pmpp=#{inspect(pmpp, limit: :infinity)} in_flight=#{
              inspect(state.in_flight)
            }"
          end)

        {:stop, state}
    end
  end
end
