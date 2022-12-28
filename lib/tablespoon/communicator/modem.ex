defmodule Tablespoon.Communicator.Modem do
  @moduledoc """
  Communication with a modem at an intersection.

  The communication is line-based.

  When we first connect, we expect an "OK" line, unless passed the "expect_ok?: false" option is passed

  To request priority at an intersection, we set one of the relays to 1:

  > "AT*RELAYOUT2=1" -> "OK"

  2 is North, 3 East, 4 South, and 5 West.

  To cancel a priority request, we set the relay to 0:

  > "AT*RELAYOUT2=0" -> "OK"

  If we receive multiple requests for priority in a given direction, we don't
  send the cancel message until the last vehicle requests a cancelation.

  > "AT*RELAYOUT3=1" -> "OK"
  > "AT*RELAYOUT3=1" -> "OK"
  > "AT*RELAYOUT3=0" (skipped, not sent)
  > "AT*RELAYOUT3=0" -> "OK"

  However, if we don't receive a cancel from the vehicle after some time
  (`@open_request_timeout`) we will send a cancellation in the background and
  log a warning.
  """
  require Logger
  @behaviour Tablespoon.Communicator

  @enforce_keys [:transport]
  defstruct @enforce_keys ++
              [
                buffer: "",
                queue: :queue.new(),
                open_vehicles: %{},
                approach_counts: %{:north => 0, :east => 0, :south => 0, :west => 0},
                expect_ok?: true,
                connection_state: :not_connected,
                id_ref: nil,
                keep_alive_ref: nil
              ]

  # how often we send a newline to keep the connection open
  @keep_alive_timeout 180_000
  # how long an in-flight request can not have a response before we consider it stale and re-connect
  @stale_query_timeout 30_000
  # how long a request can live without a cancel before we send a cancel ourselves
  @open_request_timeout 300_000

  alias Tablespoon.{Protocol.Line, Query, Transport}

  @impl Tablespoon.Communicator
  def new(transport, opts \\ []) do
    expect_ok? = Keyword.get(opts, :expect_ok?, true)
    %__MODULE__{transport: transport, expect_ok?: expect_ok?}
  end

  @impl Tablespoon.Communicator
  def connect(%__MODULE__{} = comm) do
    {:ok, comm, events} = do_close(comm, :reconnect, [])

    with {:ok, transport} <- Transport.connect(comm.transport) do
      id_ref = make_ref()

      connection_state =
        if comm.expect_ok? do
          :awaiting_ok
        else
          Kernel.send(self(), {id_ref, :timeout})
          :connected
        end

      comm = %{
        comm
        | id_ref: id_ref,
          transport: transport,
          expect_ok?: comm.expect_ok?,
          connection_state: connection_state
      }

      {:ok, comm, events}
    end
  end

  @impl Tablespoon.Communicator
  def close(%__MODULE__{} = comm) do
    comm =
      comm.queue
      |> :queue.to_list()
      |> Enum.reduce(comm, fn q, comm ->
        with %{type: :request} <- q,
             q = %{q | type: :cancel},
             {:ok, transport} <- send_query(comm, q) do
          %{comm | transport: transport}
        else
          _ -> comm
        end
      end)

    do_close(comm, :close, [])
  end

  @impl Tablespoon.Communicator
  def send(%__MODULE__{} = comm, %Query{} = q) do
    with {:ok, comm} <- check_stale_queries(comm) do
      comm = track_open_vehicles(comm, q)
      approach_counts = update_approach_counts(comm, q)

      if q.type == :request or Map.fetch!(approach_counts, q.approach) == 0 do
        case send_query(comm, q) do
          {:ok, transport} ->
            queue = :queue.in(q, comm.queue)
            comm = %{comm | transport: transport, queue: queue, approach_counts: approach_counts}
            {:ok, comm, []}

          {:error, e} ->
            {:ok, comm, [{:failed, q, e}]}
        end
      else
        # ignoring an extra cancel
        {:ok, %{comm | approach_counts: approach_counts}, [sent: q]}
      end
    end
  end

  defp track_open_vehicles(comm, q) do
    open_vehicles =
      case q.type do
        :request ->
          ref =
            Process.send_after(self(), {comm.id_ref, :query_timeout, q}, @open_request_timeout)

          track_open_vehicles_request(comm, q.vehicle_id, ref)

        :cancel ->
          track_open_vehicles_cancel(comm, q.vehicle_id)
      end

    %{comm | open_vehicles: open_vehicles}
  end

  defp track_open_vehicles_request(comm, vehicle_id, ref) do
    open_vehicles = Map.put_new_lazy(comm.open_vehicles, vehicle_id, &:queue.new/0)
    Map.update!(open_vehicles, vehicle_id, &:queue.in(ref, &1))
  end

  defp track_open_vehicles_cancel(comm, vehicle_id) do
    with {:ok, queue} <- Map.fetch(comm.open_vehicles, vehicle_id),
         {{:value, ref}, queue} <- :queue.out(queue) do
      _ = Process.cancel_timer(ref)

      if :queue.is_empty(queue) do
        Map.delete(comm.open_vehicles, vehicle_id)
      else
        Map.put(comm.open_vehicles, vehicle_id, queue)
      end
    else
      :error ->
        # couldn't find the vehicle in the map
        comm.open_vehicles

      {:empty, _queue} ->
        # I don't believe this case can happen, as we delete the entry if the
        # queue is empty above. But we handle this case anyways, in the same
        # way. -ps
        # coveralls-ignore-start
        Map.delete(comm.open_vehicles, vehicle_id)
        # coveralls-ignore-stop
    end
  end

  defp update_approach_counts(comm, q) do
    count_change =
      if q.type == :request do
        &(&1 + 1)
      else
        # ensure we never go below 0
        &max(&1 - 1, 0)
      end

    Map.update!(comm.approach_counts, q.approach, count_change)
  end

  def send_query(comm, q) do
    data =
      q
      |> query_iodata()
      |> Line.encode()

    Transport.send(comm.transport, data)
  end

  @impl Tablespoon.Communicator
  def stream(comm, message)

  def stream(%__MODULE__{id_ref: id_ref} = comm, {id_ref, :timeout}) do
    with {:ok, comm} <- check_stale_queries(comm) do
      _ = if comm.keep_alive_ref, do: Process.cancel_timer(comm.keep_alive_ref)

      case Transport.send(comm.transport, "\n") do
        {:ok, transport} ->
          ref = Process.send_after(self(), {id_ref, :timeout}, @keep_alive_timeout)
          {:ok, %{comm | keep_alive_ref: ref, transport: transport}, []}

        {:error, e} ->
          {:ok, comm, [{:error, e}]}
      end
    end
  end

  def stream(%__MODULE__{id_ref: id_ref} = comm, {id_ref, :query_timeout, query}) do
    vehicle_id = query.vehicle_id

    case Map.fetch(comm.open_vehicles, vehicle_id) do
      {:ok, queue} ->
        open_vehicles = track_open_vehicles_cancel(comm, vehicle_id)
        comm = %{comm | open_vehicles: open_vehicles}

        if :queue.is_empty(queue) do
          # this case shouldn't be possible (we delete empty queues) but we handle it anyways -ps
          # coveralls-ignore-start
          {:ok, comm, []}
          # coveralls-ignore-stop
        else
          pretend_cancel(comm, query)
        end

      :error ->
        # no open requests for this vehicle, nothing to do!
        {:ok, comm, []}
    end
  end

  def stream(%__MODULE__{} = comm, message) do
    with {:ok, transport, results} <- Transport.stream(comm.transport, message),
         {:ok, comm} <- check_stale_queries(comm) do
      comm = %{comm | transport: transport}
      Enum.reduce_while(results, {:ok, comm, []}, &handle_stream_results/2)
    end
  end

  defp pretend_cancel(comm, q) do
    cancel_query = Query.update(q, type: :cancel)
    approach_counts = update_approach_counts(comm, cancel_query)

    original_event_time_iso =
      q.event_time
      |> DateTime.from_unix!(:native)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    event_time_iso = DateTime.to_iso8601(DateTime.utc_now())

    case send_query(comm, cancel_query) do
      {:ok, transport} ->
        # we put the connection into the :awaiting_ok state to eat the
        # response to our fake cancel message.
        Logger.info(
          "sending fake cancel alias=#{q.intersection_alias} pid=#{inspect(self())} type=:cancel q_id=#{q.id} v_id=#{q.vehicle_id} approach=#{q.approach} event_time=#{event_time_iso} original_event_time=#{original_event_time_iso}"
        )

        comm = %{
          comm
          | transport: transport,
            approach_counts: approach_counts,
            connection_state: :awaiting_ok
        }

        {:ok, comm, []}

      {:error, e} ->
        do_close(comm, e, [], [{:error, e}])
    end
  end

  defp handle_stream_results({:data, binary}, {:ok, comm, events}) do
    comm = %{comm | buffer: comm.buffer <> binary}
    handle_buffer(comm, events)
  end

  defp handle_stream_results(:closed, {:ok, comm, events}) do
    {:halt, do_close(comm, :closed, events, [{:error, :closed}])}
  end

  defp handle_buffer(comm, events) do
    case Line.decode(comm.buffer) do
      {:ok, line, rest} ->
        comm = %{comm | buffer: rest}
        {:ok, comm, new_events} = handle_line(comm, line)
        handle_buffer(comm, events ++ new_events)

      {:error, :too_short} ->
        {:cont, {:ok, comm, events}}
    end
  end

  defp handle_line(comm, "") do
    {:ok, comm, []}
  end

  defp handle_line(%{connection_state: :connected} = comm, "OK") do
    case :queue.out(comm.queue) do
      {{:value, q}, queue} ->
        comm = %{comm | queue: queue}
        {:ok, comm, [sent: q]}

      {:empty, queue} ->
        comm = %{comm | queue: queue}
        _ = Logger.info("#{__MODULE__} unexpected OK response, ignoring...")
        {:ok, comm, []}
    end
  end

  defp handle_line(comm, "AT*RELAYOUT" <> _) do
    # echo of our request. sometimes the modems don't send the initial OK
    # first, so we ignore the echo either way.
    {:ok, comm, []}
  end

  defp handle_line(comm, "Unable to create ACMIMsgQ") do
    # we get these messges from modems periodically, but they don't otherwise appear to cause any problems.
    Logger.debug("#{__MODULE__} modem Unable to create ACMIMsgQ, ignoring comm=#{inspect(comm)}")
    {:ok, comm, []}
  end

  defp handle_line(%{connection_state: :connected} = comm, line) do
    error =
      if line == "ERROR" do
        :error
      else
        {:unknown, line}
      end

    {response, queue} = :queue.out(comm.queue)
    comm = %{comm | queue: queue}

    results =
      case response do
        {:value, q} ->
          [{:failed, q, error}]

        :empty ->
          _ =
            Logger.warn(
              "#{__MODULE__} unexpected response with empty queue comm=#{inspect(comm)} line=#{inspect(line)}"
            )

          []
      end

    {:ok, comm, results}
  end

  defp handle_line(%{connection_state: :awaiting_ok} = comm, "OK") do
    # we get an OK when we first connect
    comm = %{comm | connection_state: :connected}
    Kernel.send(self(), {comm.id_ref, :timeout})
    {:ok, comm, []}
  end

  defp handle_line(%{connection_state: :awaiting_ok} = comm, "picocom" <> _) do
    # picocom modems send a bunch of user-facing content when
    # connecting. it's over when we get a "Terminal ready" line.
    comm = %{comm | connection_state: :picocom_initial}
    {:ok, comm, []}
  end

  defp handle_line(%{connection_state: :picocom_initial} = comm, "Terminal ready") do
    Kernel.send(self(), {comm.id_ref, :timeout})
    comm = %{comm | connection_state: :connected}
    {:ok, comm, []}
  end

  defp handle_line(%{connection_state: :picocom_initial} = comm, _) do
    {:ok, comm, []}
  end

  defp query_iodata(%Query{} = q) do
    ["AT*RELAYOUT", request_relay(q), ?=, request_value(q)]
  end

  defp request_relay(%{approach: :north}), do: ?2
  defp request_relay(%{approach: :east}), do: ?3
  defp request_relay(%{approach: :south}), do: ?4
  defp request_relay(%{approach: :west}), do: ?5

  defp request_value(%{type: :request}), do: ?1
  defp request_value(%{type: :cancel}), do: ?0

  defp check_stale_queries(comm) do
    stale_responses =
      :queue.filter(
        fn q -> Query.processing_time(q, :millisecond) > @stale_query_timeout end,
        comm.queue
      )

    if :queue.is_empty(stale_responses) do
      {:ok, comm}
    else
      do_close(comm, :stale, [], [{:error, :stale}])
    end
  end

  defp do_close(comm, reason, events, tail_events \\ []) do
    failures =
      for q <- :queue.to_list(comm.queue) do
        {:failed, q, reason}
      end

    # cancel keep-alive timer
    _ = if comm.keep_alive_ref, do: Process.cancel_timer(comm.keep_alive_ref)

    # cancel any open vehicle timers
    comm.open_vehicles
    |> Map.values()
    |> Enum.flat_map(&:queue.to_list/1)
    |> Enum.each(&Process.cancel_timer/1)

    transport = Transport.close(comm.transport)

    comm = %__MODULE__{transport: transport, expect_ok?: comm.expect_ok?}
    {:ok, comm, events ++ failures ++ tail_events}
  end
end
