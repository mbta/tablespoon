defmodule Tablespoon.Transport.PMPPMultiplex.Child do
  @moduledoc """
  GenServer responsible for maintaining a single connection and multiplexing messages.
  """
  use GenServer
  alias Tablespoon.Protocol.PMPP
  alias Tablespoon.Transport

  defstruct [:transport, :address, buffer: "", queue: :queue.new()]

  def start_link({transport, address, name}) do
    GenServer.start_link(__MODULE__, {transport, address}, name: name)
  end

  def send({pid, ref}, iodata) do
    GenServer.call(pid, {:send, {self(), ref}, iodata})
  end

  @impl GenServer
  def init({transport, address}) do
    with {:ok, transport} <- Transport.connect(transport) do
      {:ok, %__MODULE__{transport: transport, address: address}}
    end
  end

  @impl GenServer
  def handle_call({:send, key, iodata}, _from, state) do
    %{transport: transport, queue: queue} = state
    encoded = PMPP.encode(%PMPP{address: state.address, control: :information_poll, body: iodata})
    {:ok, transport} = Transport.send(transport, encoded)
    queue = :queue.in(key, queue)
    state = %{state | transport: transport, queue: queue}
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(message, state) do
    %{transport: transport} = state

    case Transport.stream(transport, message) do
      {:ok, transport, messages} ->
        state = %{state | transport: transport}
        {:noreply, Enum.reduce(messages, state, &handle_message/2)}

      :unknown ->
        super(message, state)
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
    {{:value, {pid, ref}}, queue} = :queue.out(state.queue)
    Kernel.send(pid, {ref, {:data, pmpp.body}})
    %{state | queue: queue}
  end
end
