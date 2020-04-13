defmodule Tablespoon.Communicator.BtdTest do
  @moduledoc false
  use ExUnit.Case
  use ExUnitProperties

  alias Tablespoon.Communicator.Btd
  import Btd
  doctest Tablespoon.Communicator.Btd

  alias Tablespoon.Protocol.NTCIP1211Extended, as: NTCIP
  alias Tablespoon.Query
  alias Tablespoon.Transport.Fake, as: FakeTransport

  @group "group"
  @intersection_id 1234

  setup_all do
    log_level = Logger.level()
    Logger.configure(level: :error)

    on_exit(fn ->
      Logger.configure(level: log_level)
    end)

    :ok
  end

  describe "send/2" do
    test "sends a NTCIP1211 request query and receives an ack" do
      query =
        Query.new(
          id: 1,
          type: :request,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm =
        Btd.new(
          FakeTransport.new(),
          group: @group,
          intersection_id: @intersection_id
        )

      {:ok, comm, []} = Btd.connect(comm)
      {:ok, comm, []} = Btd.send(comm, query)

      ntcip_message = %NTCIP.PriorityRequest{
        id: 1,
        vehicle_id: "1",
        vehicle_class: 2,
        vehicle_class_level: 0,
        strategy: 3,
        time_of_service_desired: 0,
        time_of_estimated_departure: 0,
        intersection_id: @intersection_id
      }

      ntcip =
        NTCIP.encode(%NTCIP{
          group: @group,
          pdu_type: :response,
          request_id: 0,
          message: ntcip_message
        })

      {:ok, comm, [sent: ^query]} = Btd.stream(comm, ntcip)
      [sent_packet] = comm.transport.sent

      assert {:ok, %NTCIP{group: @group, pdu_type: :set, message: ^ntcip_message}} =
               NTCIP.decode(sent_packet)
    end

    test "sends a NTCIP1211 cancel query and receives an ack" do
      query =
        Query.new(
          id: 1,
          type: :cancel,
          vehicle_id: "1",
          intersection_alias: "int",
          approach: :south,
          event_time: System.system_time()
        )

      comm =
        Btd.new(
          FakeTransport.new(),
          group: @group,
          intersection_id: @intersection_id
        )

      {:ok, comm, []} = Btd.connect(comm)
      {:ok, comm, []} = Btd.send(comm, query)

      ntcip_message = %NTCIP.PriorityCancel{
        id: 1,
        vehicle_id: "1",
        vehicle_class: 2,
        vehicle_class_level: 0,
        strategy: 3,
        intersection_id: @intersection_id
      }

      ntcip =
        NTCIP.encode(%NTCIP{
          group: @group,
          pdu_type: :response,
          request_id: 0,
          message: ntcip_message
        })

      {:ok, comm, [sent: ^query]} = Btd.stream(comm, ntcip)
      [sent_packet] = comm.transport.sent

      assert {:ok, %NTCIP{group: @group, pdu_type: :set, message: ^ntcip_message}} =
               NTCIP.decode(sent_packet)
    end
  end

  describe "stream/2" do
    property "always returns a response" do
      check all(query_responses <- list_of(query_response(), min_length: 1)) do
        comm =
          Btd.new(
            FakeTransport.new(),
            group: @group,
            intersection_id: @intersection_id,
            timeout: 0
          )

        {:ok, comm, []} = Btd.connect(comm)

        {:ok, _comm, events} =
          Enum.reduce(query_responses, {:ok, comm, []}, fn {query, response},
                                                           {:ok, comm, events} ->
            {:ok, comm, send_events} = Btd.send(comm, query)
            {:ok, comm, stream_events} = Btd.stream(comm, stream_response(comm, response))
            {:ok, comm, receive_events} = maybe_receive_events(comm, [])
            {:ok, comm, events ++ send_events ++ stream_events ++ receive_events}
          end)

        # closes send an extra {:error, :closed} event
        close_count = Enum.count(query_responses, &(elem(&1, 1) == :close))
        assert length(events) == length(query_responses) + close_count

        for event <- events do
          assert elem(event, 0) in [:sent, :failed, :error]
        end
      end
    end
  end

  defp maybe_receive_events(comm, events, ref \\ nil) do
    ref =
      if is_nil(ref) do
        ref = make_ref()
        Kernel.send(self(), ref)
        ref
      else
        ref
      end

    receive do
      ^ref ->
        {:ok, comm, events}

      x ->
        case Btd.stream(comm, x) do
          :unknown ->
            maybe_receive_events(comm, events, ref)

          {:ok, comm, new_events} ->
            maybe_receive_events(comm, events ++ new_events, ref)
        end
    end
  end

  defp stream_response(comm, :succeed) do
    data = List.last(comm.transport.sent)
    {:ok, ntcip} = NTCIP.decode(IO.iodata_to_binary(data))
    ntcip_response = NTCIP.encode(%{ntcip | pdu_type: :response})
    IO.iodata_to_binary(ntcip_response)
  end

  defp stream_response(comm, :extra) do
    data = List.last(comm.transport.sent)
    {:ok, ntcip} = NTCIP.decode(IO.iodata_to_binary(data))
    ntcip_response = NTCIP.encode(%{ntcip | pdu_type: :response})
    data = IO.iodata_to_binary(ntcip_response)
    # send ourselves an extra copy of the response
    Kernel.send(self(), data)

    data
  end

  defp stream_response(comm, :change_group) do
    data = List.last(comm.transport.sent)
    {:ok, ntcip} = NTCIP.decode(IO.iodata_to_binary(data))
    ntcip_response = NTCIP.encode(%{ntcip | group: "other group", pdu_type: :response})
    IO.iodata_to_binary(ntcip_response)
  end

  defp stream_response(_comm, :drop) do
    :empty
  end

  defp stream_response(_comm, :invalid_ntcip) do
    "invalid body"
  end

  defp stream_response(_comm, :close) do
    :close
  end

  defp query_response do
    gen all(
          response <- response(),
          query <- query()
        ) do
      {query, response}
    end
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

  defp response do
    frequency([
      {10, :succeed},
      {2, :drop},
      {1, :invalid_ntcip},
      {1, :change_group},
      {2, :close}
    ])
  end
end
