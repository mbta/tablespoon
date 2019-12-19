defmodule Tablespoon.Communicator.Btd do
  @moduledoc """
  Communication with the Boston Transportation Department (BTD).

  The communication is over NTCIP1211 Extended packets.

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
  alias Tablespoon.{Query, Transport, UniqueRangeCounter}

  require Logger

  @enforce_keys [:transport, :group, :intersection_id, :ref]
  defstruct @enforce_keys ++ [timeout: 5_000, next_id: 1, in_flight: %{}]

  @impl Tablespoon.Communicator
  def new(transport, opts) do
    struct!(__MODULE__, [transport: transport, ref: make_ref()] ++ opts)
  end

  @impl Tablespoon.Communicator
  def connect(%__MODULE__{} = comm) do
    with {:ok, transport} <- Transport.connect(comm.transport) do
      {:ok, %{comm | transport: transport}}
    end
  end

  @impl Tablespoon.Communicator
  def send(%__MODULE__{} = comm, %Query{} = q) do
    # ensure the request ID is always one byte
    request_id = UniqueRangeCounter.unique_integer(:btd_request_id, -128, 127)

    ntcip =
      NTCIP.encode(%NTCIP{
        group: comm.group,
        pdu_type: :set,
        request_id: request_id,
        message: ntcip_message(comm, q)
      })

    case Transport.send(comm.transport, ntcip) do
      {:ok, transport} ->
        # send ourselves a message to bail out if we don't get a response
        timer = send_after(self(), {comm.ref, :timeout, comm.next_id, q}, comm.timeout)
        in_flight = Map.put(comm.in_flight, comm.next_id, {q, timer})

        {:ok,
         %{comm | next_id: next_id(comm.next_id), in_flight: in_flight, transport: transport}, []}

      {:error, e} ->
        {:ok, comm, [{:failed, q, e}]}
    end
  end

  @impl Tablespoon.Communicator
  def stream(%__MODULE__{ref: ref} = comm, {ref, :timeout, id, q}) do
    case Map.get(comm.in_flight, id) do
      {^q, _} ->
        in_flight = Map.delete(comm.in_flight, id)
        comm = %{comm | in_flight: in_flight}
        {:ok, comm, [{:failed, q, :timeout}]}

      _ ->
        :unknown
    end
  end

  def stream(%__MODULE__{}, {ref, :timeout, _id, _}) when is_reference(ref) do
    # timeout from an earlier version of this connection
    :unknown
  end

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
      strategy: ntcip_strategy(q.approach),
      intersection_id: comm.intersection_id
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
    case NTCIP.decode(binary) do
      {:ok, ntcip} ->
        handle_ntcip(comm, ntcip, events)

      {:error, e} ->
        _ =
          Logger.warn(fn ->
            "unexpected error decoding NTCIP comm=#{inspect(comm)} error=#{inspect(e)} body=#{
              inspect(binary, limit: :infinity)
            }"
          end)

        {:cont, {:ok, comm, events}}
    end
  end

  defp handle_stream_results(:closed, {:ok, comm, events}) do
    failed =
      for {q, timer} <- Map.values(comm.in_flight) do
        _ = Process.cancel_timer(timer)
        {:failed, q, :closed}
      end

    comm = %{comm | next_id: 1, in_flight: %{}}
    {:halt, {:ok, comm, events ++ failed ++ [{:error, :closed}]}}
  end

  defp handle_ntcip(%{group: group} = comm, %{group: group, pdu_type: :response} = ntcip, events) do
    case Map.pop(comm.in_flight, ntcip.message.id) do
      {nil, _} ->
        # we got a response to a message we weren't waiting for. This isn't a
        # big deal, as we'll have already sent a :timeout reply if it was a
        # message we wanted.
        _ =
          Logger.debug(fn ->
            "unexpected response for message comm=#{inspect(comm)} message=#{inspect(ntcip)}"
          end)

        {:cont, {:ok, comm, events}}

      {{query, timer}, in_flight} ->
        _ = Process.cancel_timer(timer)
        events = [sent: query] ++ events
        comm = %{comm | in_flight: in_flight}
        {:cont, {:ok, comm, events}}
    end
  end

  defp handle_ntcip(comm, ntcip, events) do
    _ =
      Logger.warn(fn ->
        "unexpected NTCIP1211 message comm=#{inspect(comm)} message=#{inspect(ntcip)}"
      end)

    {:cont, {:ok, comm, events}}
  end

  defp send_after(pid, message, after_time) when after_time > 0 do
    Process.send_after(pid, message, after_time)
  end

  defp send_after(pid, message, _after_time) do
    Kernel.send(pid, message)
    # fake timer
    make_ref()
  end
end
