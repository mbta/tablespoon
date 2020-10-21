defmodule Tablespoon.Communicator.ModemTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Tablespoon.Communicator.Modem
  alias Tablespoon.Query
  alias Tablespoon.Transport.Fake, as: FakeTransport

  describe "send/2" do
    test "sends a query and acknowledges" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, comm, events} = process_data(comm, ["OK", "\r", "\r\n", "\r\n", "OK\r\n"], events)
      assert events == [{:sent, query}]
      assert comm.transport.sent == ["AT*RELAYOUT4=1\n"]
    end

    test "does not require an initial OK if expect_ok? is false" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new(), expect_ok?: false)
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, comm, events} = process_data(comm, ["OK", "\r", "\r\n", "\r\n"], events)
      assert events == [{:sent, query}]
      assert comm.transport.sent == ["AT*RELAYOUT4=1\n"]
    end

    test "if connected to a picocom modem, does not connect until the debugging output is finished" do
      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)
      refute comm.connection_state == :connected
      {:ok, comm, []} = process_data(comm, ["picocom v3.1\n\nOK\n"], [])
      refute comm.connection_state == :connected
      {:ok, comm, []} = process_data(comm, ["Terminal ready\n"], [])
      assert comm.connection_state == :connected
    end

    test "handles errors in the response" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, _comm, events} = process_data(comm, ["OK\n", "ERROR\n"], events)
      assert events == [{:failed, query, :error}]
    end

    test "handles errors without a request" do
      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)

      log =
        capture_log(fn ->
          {:ok, _comm, events} = process_data(comm, ["OK\n", "ERROR\n"], [])
          assert events == []
        end)

      assert log =~ "unexpected response with empty queue"
    end

    test "acks queries in FIFO order" do
      request =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      cancel =
        Query.new(
          id: 1,
          type: :cancel,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, request)
      {:ok, comm, events2} = Modem.send(comm, cancel)
      {:ok, comm, events} = process_data(comm, ["OK\nOK\nOK\n"], events ++ events2)
      assert comm.transport.sent == ["AT*RELAYOUT4=1\n", "AT*RELAYOUT4=0\n"]
      assert events == [{:sent, request}, {:sent, cancel}]
    end

    test "does not send an extra cancel if two vehicles request TSP" do
      vehicle_ids = ["1", "2"]

      queries =
        for type <- [:request, :cancel],
            vehicle_id <- vehicle_ids do
          Query.new(
            id: :erlang.unique_integer([:monotonic]),
            type: type,
            vehicle_id: vehicle_id,
            intersection_alias: "int",
            approach: :north,
            event_time: System.system_time()
          )
        end

      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)

      {:ok, comm, events} =
        Enum.reduce(queries, {:ok, comm, []}, fn q, {:ok, comm, events} ->
          {:ok, comm, new_events} = Modem.send(comm, q)
          {:ok, comm, events ++ new_events}
        end)

      {:ok, comm, events} = process_data(comm, ["OK\nOK\nOK\nOK\n"], events)
      assert comm.transport.sent == ["AT*RELAYOUT2=1\n", "AT*RELAYOUT2=1\n", "AT*RELAYOUT2=0\n"]
      assert [sent: _, sent: _, sent: _, sent: _] = events
    end

    test "waits for an OK for an initial cancel" do
      query =
        Query.new(
          id: :erlang.unique_integer([:monotonic]),
          type: :cancel,
          vehicle_id: "1234",
          intersection_alias: "int",
          approach: :north,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)

      {:ok, comm, events} = Modem.send(comm, query)

      {:ok, comm, events} = process_data(comm, ["OK\nOK\n"], events)
      assert comm.transport.sent == ["AT*RELAYOUT2=0\n"]
      assert [sent: _] = events
    end

    test "reconnecting while waiting for a response returns failed" do
      query =
        Query.new(
          id: :erlang.unique_integer([:monotonic]),
          type: :request,
          vehicle_id: "1234",
          intersection_alias: "int",
          approach: :north,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)

      {:ok, comm, events} = Modem.send(comm, query)

      {:ok, comm, events} = process_data(comm, ["OK\n"], events)
      assert comm.transport.sent == ["AT*RELAYOUT2=1\n"]
      {:ok, comm, connect_events} = Modem.connect(comm)
      {:ok, _comm, events} = process_data(comm, ["OK\nOK\n"], events ++ connect_events)
      assert [{:failed, ^query, :reconnect}] = events
    end

    test "can handle an echo without an initial OK" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)

      {:ok, comm, events} = process_data(comm, ["AT*RELAYOUT4=1\r\n", "OK\r\n"], events)
      assert events == []

      {:ok, _comm, events} = process_data(comm, ["OK\r\n"], events)
      assert events == [{:sent, query}]
    end

    test "timeout sends an empty new line" do
      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, []} = process_data(comm, [{comm.id_ref, :timeout}], [])
      assert comm.transport.sent == ["\n"]
    end

    test "timeout with stale messages replies with an error" do
      query =
        Query.new(
          id: 1,
          type: :cancel,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time(),
          received_at_mono: System.monotonic_time() - 100_000_000_000
        )

      comm = Modem.new(FakeTransport.new())
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, comm, events} = process_data(comm, [{comm.id_ref, :timeout}], events)
      assert events == [{:failed, query, :stale}, {:error, :stale}]
      assert comm.transport.sent == ["AT*RELAYOUT4=0\n"]
    end

    @tag :capture_log
    test "vehicle timeout sends a cancel message" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm = Modem.new(FakeTransport.new(), expect_ok?: false)
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)

      {:ok, comm, events} =
        process_data(comm, ["OK\r\n", {comm.id_ref, :query_timeout, query}, "OK\r\n"], events)

      assert events == [{:sent, query}]
      assert comm.transport.sent == ["AT*RELAYOUT4=1\n", "AT*RELAYOUT4=0\n"]
      assert comm.approach_counts.south == 0
      assert comm.open_vehicles == %{}
    end

    test "vehicle timeout after a cancel request does not send an extra cancel message" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      cancel_query = Query.update(query, type: :cancel)

      next_query = Query.update(query, vehicle_id: "2")

      comm = Modem.new(FakeTransport.new(), expect_ok?: false)
      {:ok, comm, []} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, comm, events2} = Modem.send(comm, cancel_query)
      {:ok, comm, events3} = Modem.send(comm, next_query)

      {:ok, comm, events} =
        process_data(
          comm,
          ["OK\r\n", "OK\r\n", {comm.id_ref, :query_timeout, query}, "OK\r\n"],
          events ++ events2 ++ events3
        )

      # we expect to have sent requests for all three queries, as well as
      # having sent the relayout messages
      assert events == [{:sent, query}, {:sent, cancel_query}, {:sent, next_query}]
      assert comm.transport.sent == ["AT*RELAYOUT4=1\n", "AT*RELAYOUT4=0\n", "AT*RELAYOUT4=1\n"]
      assert comm.approach_counts.south == 1
      assert "1" not in Map.keys(comm.open_vehicles)
      assert :queue.len(comm.open_vehicles["2"]) == 1
    end
  end

  defp process_data(comm, datas, events) do
    Enum.reduce_while(datas, {:ok, comm, events}, fn data, {:ok, comm, events} ->
      case Modem.stream(comm, data) do
        {:ok, comm, new_events} ->
          {:cont, {:ok, comm, events ++ new_events}}

        other ->
          {:halt, other}
      end
    end)
  end

  describe "stream/2" do
    property "always returns sent or failed for a query" do
      check all(query_responses <- list_of(query_response(), min_length: 1)) do
        comm = Modem.new(FakeTransport.new(), expect_ok?: false)
        {:ok, comm, []} = Modem.connect(comm)

        {:ok, _comm, events} =
          Enum.reduce(query_responses, {:ok, comm, []}, fn {query, response},
                                                           {:ok, comm, events} ->
            sent_before = comm.transport.sent
            {:ok, comm, new_events} = Modem.send(comm, query)

            {:ok, comm, new_events} =
              if sent_before != comm.transport.sent do
                process_data(comm, response, new_events)
              else
                # if there were too many requests w/o a cancel, then we don't
                # send anything and don't get any new events
                {:ok, comm, new_events}
              end

            if :close in response do
              # reconnect if we got disconnected
              {:ok, comm, connect_events} = Modem.connect(comm)
              {:ok, comm, events ++ new_events ++ connect_events}
            else
              {:ok, comm, events ++ new_events}
            end
          end)

        events = Enum.filter(events, &(elem(&1, 0) in [:sent, :failed]))
        assert length(events) == length(query_responses)

        for {{query, _response}, event} <- Enum.zip(query_responses, events) do
          assert elem(event, 1) == query
        end
      end
    end
  end

  defp query_response do
    tuple({
      query(),
      response()
    })
  end

  defp query do
    gen all(
          type <- one_of([:request, :cancel]),
          approach <- one_of([:north, :east, :south, :west])
        ) do
      Query.new(
        id: 1,
        type: type,
        vehicle_id: "1",
        intersection_alias: "int",
        approach: approach,
        event_time: System.system_time()
      )
    end
  end

  def response do
    one_of([
      constant(["OK\n"]),
      constant(["ERROR\n"]),
      constant(["unknown\n"]),
      constant([:close])
    ])
  end
end
