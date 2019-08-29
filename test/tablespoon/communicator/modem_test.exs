defmodule Tablespoon.Communicator.ModemTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

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
      {:ok, comm} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, comm, events} = process_data(comm, ["OK", "\r", "\r\n", "\r\n", "OK\r\n"], events)
      assert events == [{:sent, query}]
      assert comm.transport.sent == ["AT*RELAYOUT4=1\n"]
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
      {:ok, comm} = Modem.connect(comm)
      {:ok, comm, events} = Modem.send(comm, query)
      {:ok, _comm, events} = process_data(comm, ["OK\n", "ERROR\n"], events)
      assert events == [{:failed, query, :error}]
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
      {:ok, comm} = Modem.connect(comm)
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
      {:ok, comm} = Modem.connect(comm)

      {:ok, comm, events} =
        Enum.reduce(queries, {:ok, comm, []}, fn q, {:ok, comm, events} ->
          {:ok, comm, new_events} = Modem.send(comm, q)
          {:ok, comm, events ++ new_events}
        end)

      {:ok, comm, events} = process_data(comm, ["OK\nOK\nOK\nOK\n"], events)
      assert comm.transport.sent == ["AT*RELAYOUT2=1\n", "AT*RELAYOUT2=1\n", "AT*RELAYOUT2=0\n"]
      assert [sent: _, sent: _, sent: _, sent: _] = events
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
    test "reconnects if the transport closes the connection" do
      comm = Modem.new(FakeTransport.new())
      {:ok, comm} = Modem.connect(comm)
      {:ok, comm, []} = Modem.stream(comm, "partial line")
      {:ok, comm, []} = Modem.stream(comm, :close)
      assert comm.buffer == ""
      assert comm.transport.connect_count == 2
    end

    property "always returns sent or failed for a query" do
      check all query_responses <- list_of(query_response(), min_length: 1) do
        comm = Modem.new(FakeTransport.new())
        {:ok, comm} = Modem.connect(comm)
        {:ok, comm, []} = Modem.stream(comm, "OK\n")

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

            {:ok, comm, events ++ new_events}
          end)

        assert length(events) == length(query_responses)

        for {{query, _response}, event} <- Enum.zip(query_responses, events) do
          assert elem(event, 0) in [:sent, :failed]
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
    gen all type <- one_of([:request, :cancel]),
            approach <- one_of([:north, :east, :south, :west]) do
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
      constant([:close, "OK\n"])
    ])
  end
end
