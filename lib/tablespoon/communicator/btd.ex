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

  @enforce_keys [:transport, :address, :group, :intersection_id, :ref]
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
    ntcip =
      NTCIP.encode(%NTCIP{
        group: comm.group,
        pdu_type: :set,
        request_id: 0,
        message: ntcip_message(comm, q)
      })

    pmpp = PMPP.encode(%PMPP{address: comm.address, control: :information_poll, body: ntcip})

    with {:ok, transport} <- Transport.send(comm.transport, pmpp) do
      # send ourselves a message to bail out if we don't get a response
      timer = send_after(self(), {comm.ref, :timeout, comm.next_id, q}, comm.timeout)
      in_flight = Map.put(comm.in_flight, comm.next_id, {q, timer})

      {:ok, %{comm | next_id: next_id(comm.next_id), in_flight: in_flight, transport: transport},
       []}
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
    case PMPP.decode(binary) do
      {:ok, pmpp, ""} ->
        handle_pmpp(comm, pmpp, events)

      {:error, e, _} ->
        _ =
          Logger.warn(fn ->
            "unexpected error decoding PMPP comm=#{inspect(comm)} error=#{inspect(e)} body=#{
              inspect(binary)
            }"
          end)

        {:cont, {:ok, comm, events}}
    end
  end

  defp handle_stream_results(:closed, {:ok, comm, events}) do
    case Transport.connect(comm.transport) do
      {:ok, transport} ->
        failed =
          for {q, timer} <- Map.values(comm.in_flight) do
            Process.cancel_timer(timer)
            {:failed, q, :closed}
          end

        comm = %{comm | transport: transport, ref: make_ref(), next_id: 1, in_flight: %{}}
        {:halt, {:ok, %{comm | transport: transport}, events ++ failed}}

      e ->
        {:halt, e}
    end
  end

  defp handle_pmpp(%{address: address} = comm, %{address: address} = pmpp, events) do
    case NTCIP.decode(pmpp.body) do
      {:ok, ntcip} ->
        handle_nctip(comm, ntcip, events)

      {:error, e} ->
        _ =
          Logger.warn(fn ->
            "unexpected error decoding NTCIP comm=#{inspect(comm)} error=#{inspect(e)} body=#{
              inspect(pmpp.body)
            }"
          end)

        {:cont, {:ok, comm, events}}
    end
  end

  defp handle_pmpp(comm, pmpp, events) do
    _ =
      Logger.warn(fn ->
        "unexpected PMPP message comm=#{inspect(comm)} message=#{inspect(pmpp)}"
      end)

    {:cont, {:ok, comm, events}}
  end

  defp handle_nctip(%{group: group} = comm, %{group: group, pdu_type: :response} = ntcip, events) do
    case Map.pop(comm.in_flight, ntcip.message.id) do
      {nil, _} ->
        _ =
          Logger.warn(fn ->
            "unexpected response for message comm=#{inspect(comm)} message=#{ntcip}"
          end)

        {:cont, {:ok, comm, events}}

      {{query, timer}, in_flight} ->
        Process.cancel_timer(timer)
        events = [sent: query] ++ events
        comm = %{comm | in_flight: in_flight}
        {:cont, {:ok, comm, events}}
    end
  end

  defp handle_nctip(comm, ntcip, events) do
    _ =
      Logger.warn(fn ->
        "unexpected NTCIP1211 message comm=#{inspect(comm)} message=#{inspect(ntcip)}"
      end)

    {:cont, {:ok, comm, events}}
  end

  defp send_after(pid, message, 0) do
    Kernel.send(pid, message)
    # fake timer
    make_ref()
  end

  defp send_after(pid, message, after_time) do
    Process.send_after(pid, message, after_time)
  end
end
