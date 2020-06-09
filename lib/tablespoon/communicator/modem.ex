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
  """
  require Logger
  @behaviour Tablespoon.Communicator

  @enforce_keys [:transport]
  defstruct @enforce_keys ++
              [
                buffer: "",
                queue: :queue.new(),
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

  alias Tablespoon.{Protocol.Line, Query, Transport}

  @impl Tablespoon.Communicator
  def new(transport, opts \\ []) do
    expect_ok? = Keyword.get(opts, :expect_ok?, true)
    %__MODULE__{transport: transport, expect_ok?: expect_ok?}
  end

  @impl Tablespoon.Communicator
  def connect(%__MODULE__{} = comm) do
    with {:ok, transport} <- Transport.connect(comm.transport) do
      failures =
        for q <- :queue.to_list(comm.queue) do
          {:failed, q, :reconnect}
        end

      id_ref = make_ref()

      connection_state =
        if comm.expect_ok? do
          :awaiting_ok
        else
          Kernel.send(self(), {id_ref, :timeout})
          :connected
        end

      comm = %__MODULE__{
        id_ref: id_ref,
        transport: transport,
        expect_ok?: comm.expect_ok?,
        connection_state: connection_state
      }

      {:ok, comm, failures}
    end
  end

  @impl Tablespoon.Communicator
  def send(%__MODULE__{} = comm, %Query{} = q) do
    with {:ok, comm} <- check_stale_queries(comm) do
      count_change =
        if q.type == :request do
          &(&1 + 1)
        else
          # ensure we never go below 0
          &max(&1 - 1, 0)
        end

      approach_counts = Map.update!(comm.approach_counts, q.approach, count_change)

      if q.type == :request or Map.fetch!(approach_counts, q.approach) == 0 do
        data =
          q
          |> query_iodata()
          |> Line.encode()

        case Transport.send(comm.transport, data) do
          {:ok, transport} ->
            queue = :queue.in(q, comm.queue)

            {:ok, %{comm | transport: transport, queue: queue, approach_counts: approach_counts},
             []}

          {:error, e} ->
            {:ok, comm, [{:failed, q, e}]}
        end
      else
        # ignoring an extra cancel
        {:ok, %{comm | approach_counts: approach_counts}, [sent: q]}
      end
    end
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

  def stream(%__MODULE__{} = comm, message) do
    with {:ok, transport, results} <- Transport.stream(comm.transport, message),
         {:ok, comm} <- check_stale_queries(comm) do
      comm = %{comm | transport: transport}
      Enum.reduce_while(results, {:ok, comm, []}, &handle_stream_results/2)
    end
  end

  defp handle_stream_results({:data, binary}, {:ok, comm, events}) do
    comm = %{comm | buffer: comm.buffer <> binary}
    handle_buffer(comm, events)
  end

  defp handle_stream_results(:closed, {:ok, comm, events}) do
    {:halt, do_close(comm, :closed, events)}
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
              "#{__MODULE__} unexpected response with empty queue comm=#{inspect(comm)} line=#{
                inspect(line)
              }"
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
      do_close(comm, :stale, [])
    end
  end

  defp do_close(comm, reason, events) do
    failures =
      for q <- :queue.to_list(comm.queue) do
        {:failed, q, reason}
      end

    _ = if comm.keep_alive_ref, do: Process.cancel_timer(comm.keep_alive_ref)
    comm = %__MODULE__{transport: comm.transport, expect_ok?: comm.expect_ok?}
    {:ok, comm, events ++ failures ++ [{:error, reason}]}
  end
end
