defmodule Tablespoon.Communicator.Btd do
  @moduledoc """
  Communication with the Boston Transportation Department (BTD).

  The communication is over PMPP-wrapped NTCIP1211 Extended packets.

  - address: passed-in
  - group: passed-in
  - id: always 0
  - id in message: increases with each request, up to 255 where it wraps back to 1
  - vehicle_id: the vehicle's ID
  - vehicle_class: always 2
  - vehicle_class_level: always 0
  - strategy: 1 - North, 2 - East, 3 - South, 4 - West
  - time_of_service_desired: always 0
  - time_of_estimated_departure: always 0
  - intersection_id: passed-in
  """
  @behaviour Tablespoon.Communicator

  alias Tablespoon.Protocol.NTCIP1211Extended, as: NTCIP
  alias Tablespoon.Protocol.PMPP
  alias Tablespoon.{Query, Transport}

  require Logger

  @enforce_keys [:transport, :address, :group, :intersection_id]
  defstruct @enforce_keys ++ [next_id: 1, in_flight: %{}]

  @impl Tablespoon.Communicator
  def new(transport, opts) do
    struct!(__MODULE__, [transport: transport] ++ opts)
  end

  @impl Tablespoon.Communicator
  def connect(%__MODULE__{} = comm) do
    with {:ok, transport} <- Transport.connect(comm.transport) do
      {:ok, %{comm | transport: transport}}
    end
  end

  @impl Tablespoon.Communicator
  def send(%__MODULE__{} = comm, %Query{} = q) do
    ntcip =
      NTCIP.encode(%NTCIP{
        group: comm.group,
        pdu_type: :set,
        request_id: 0,
        message: ntcip_message(comm, q)
      })

    pmpp = PMPP.encode(%PMPP{address: comm.address, control: :information_poll, body: ntcip})

    with {:ok, transport} <- Transport.send(comm.transport, pmpp) do
      in_flight = Map.put(comm.in_flight, comm.next_id, q)

      {:ok, %{comm | next_id: next_id(comm.next_id), in_flight: in_flight, transport: transport},
       []}
    end
  end

  @impl Tablespoon.Communicator
  def stream(%__MODULE__{} = comm, message) do
    with {:ok, transport, results} <- Transport.stream(comm.transport, message) do
      comm = %{comm | transport: transport}
      Enum.reduce_while(results, {:ok, comm, []}, &handle_stream_results/2)
    end
  end

  defp ntcip_message(comm, %{type: :request} = q) do
    %NTCIP.PriorityRequest{
      id: comm.next_id,
      vehicle_id: q.vehicle_id,
      vehicle_class: 2,
      vehicle_class_level: 0,
      strategy: ntcip_strategy(q.approach),
      time_of_service_desired: 0,
      time_of_estimated_departure: 0,
      intersection_id: comm.intersection_id
    }
  end

  defp ntcip_message(comm, %{type: :cancel} = q) do
    %NTCIP.PriorityCancel{
      id: comm.next_id,
      vehicle_id: q.vehicle_id,
      vehicle_class: 2,
      vehicle_class_level: 0,
      strategy: ntcip_strategy(q.approach)
    }
  end

  defp ntcip_strategy(:north), do: 1
  defp ntcip_strategy(:east), do: 2
  defp ntcip_strategy(:south), do: 3
  defp ntcip_strategy(:west), do: 4

  @doc """
  Return the next valid ID, given the current ID.

  iex> next_id(1)
  2

  iex> next_id(254)
  255

  iex> next_id(255)
  1
  """
  def next_id(int) when int < 255 do
    int + 1
  end

  def next_id(_) do
    1
  end

  defp handle_stream_results({:data, binary}, {:ok, comm, events}) do
    {:ok, pmpp, ""} = PMPP.decode(binary)
    handle_pmpp(comm, pmpp, events)
  end

  defp handle_stream_results(:closed, {:ok, comm, events}) do
    case Transport.connect(comm.transport) do
      {:ok, transport} ->
        {:halt, {:ok, %{comm | transport: transport}, events}}

      e ->
        {:halt, e}
    end
  end

  defp handle_pmpp(%{address: address} = comm, %{address: address} = pmpp, events) do
    {:ok, ntcip} = NTCIP.decode(pmpp.body)
    handle_nctip(comm, ntcip, events)
  end

  defp handle_nctip(%{group: group} = comm, %{group: group, pdu_type: :response} = ntcip, events) do
    {query, in_flight} = Map.pop(comm.in_flight, ntcip.message.id)
    events = [sent: query] ++ events
    comm = %{comm | in_flight: in_flight}
    {:cont, {:ok, comm, events}}
  end
end
