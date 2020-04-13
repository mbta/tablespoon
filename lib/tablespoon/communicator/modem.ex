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
  @behaviour Tablespoon.Communicator

  @enforce_keys [:transport]
  defstruct @enforce_keys ++
              [
                buffer: "",
                queue: :queue.new(),
                approach_counts: %{:north => 0, :east => 0, :south => 0, :west => 0},
                expect_ok?: true,
                connected?: false
              ]

  alias Tablespoon.{Protocol.Line, Query, Transport}

  @impl Tablespoon.Communicator
  def new(transport, opts \\ []) do
    expect_ok? = Keyword.get(opts, :expect_ok?, true)
    %__MODULE__{transport: transport, expect_ok?: expect_ok?}
  end

  @impl Tablespoon.Communicator
  def connect(%__MODULE__{} = comm) do
    with {:ok, transport} <- Transport.connect(comm.transport) do
      comm = %{comm | transport: transport}

      comm =
        if comm.expect_ok? do
          comm
        else
          %{comm | connected?: true}
        end

      {:ok, comm, []}
    end
  end

  @impl Tablespoon.Communicator
  def send(%__MODULE__{} = comm, %Query{} = q) do
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

  @impl Tablespoon.Communicator
  def stream(%__MODULE__{} = comm, message) do
    with {:ok, transport, results} <- Transport.stream(comm.transport, message) do
      comm = %{comm | transport: transport}
      Enum.reduce_while(results, {:ok, comm, []}, &handle_stream_results/2)
    end
  end

  defp handle_stream_results({:data, binary}, {:ok, comm, events}) do
    comm = %{comm | buffer: comm.buffer <> binary}
    handle_buffer(comm, events)
  end

  defp handle_stream_results(:closed, {:ok, comm, events}) do
    failures =
      for q <- :queue.to_list(comm.queue) do
        {:failed, q, :closed}
      end

    comm = %__MODULE__{transport: comm.transport, expect_ok?: comm.expect_ok?}
    {:halt, {:ok, comm, events ++ failures ++ [{:error, :closed}]}}
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

  defp handle_line(%{connected?: true} = comm, "OK") do
    {{:value, q}, queue} = :queue.out(comm.queue)
    comm = %{comm | queue: queue}
    {:ok, comm, [sent: q]}
  end

  defp handle_line(comm, "AT*RELAYOUT" <> _) do
    # echo of our request. sometimes the modems don't send the initial OK
    # first, so we ignore the echo either way.
    {:ok, comm, []}
  end

  defp handle_line(%{connected?: true} = comm, line) do
    error =
      if line == "ERROR" do
        :error
      else
        {:unknown, line}
      end

    {{:value, q}, queue} = :queue.out(comm.queue)
    comm = %{comm | queue: queue}
    {:ok, comm, [{:failed, q, error}]}
  end

  defp handle_line(%{connected?: false} = comm, "OK") do
    # we get an OK when we first connect
    comm = %{comm | connected?: true}
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
end
