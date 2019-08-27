defmodule Tablespoon.Communicator.BtdTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Tablespoon.Communicator.Btd
  import Btd
  doctest Tablespoon.Communicator.Btd

  alias Tablespoon.Protocol.NTCIP1211Extended, as: NTCIP
  alias Tablespoon.Protocol.PMPP
  alias Tablespoon.Query
  alias Tablespoon.Transport.Fake, as: FakeTransport

  @group "group"
  @address 12
  @intersection_id 1234

  describe "send/2" do
    test "sends a PMPP/NTCIP1211 request query and receives an ack" do
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
          address: @address,
          intersection_id: @intersection_id
        )

      {:ok, comm} = Btd.connect(comm)
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

      pmpp = PMPP.encode(%PMPP{address: @address, control: :information_poll, body: ntcip})

      {:ok, comm, [sent: ^query]} = Btd.stream(comm, pmpp)
      [sent_packet] = comm.transport.sent

      assert {:ok, %PMPP{address: @address, control: :information_poll, body: ntcip_body}, ""} =
               PMPP.decode(sent_packet)

      assert {:ok, %NTCIP{group: @group, pdu_type: :set, request_id: 0, message: ^ntcip_message}} =
               NTCIP.decode(ntcip_body)
    end

    test "sends a PMPP/NTCIP1211 cancel query and receives an ack" do
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
          address: @address,
          intersection_id: @intersection_id
        )

      {:ok, comm} = Btd.connect(comm)
      {:ok, comm, []} = Btd.send(comm, query)

      ntcip_message = %NTCIP.PriorityCancel{
        id: 1,
        vehicle_id: "1",
        vehicle_class: 2,
        vehicle_class_level: 0,
        strategy: 3
      }

      ntcip =
        NTCIP.encode(%NTCIP{
          group: @group,
          pdu_type: :response,
          request_id: 0,
          message: ntcip_message
        })

      pmpp = PMPP.encode(%PMPP{address: @address, control: :information_poll, body: ntcip})

      {:ok, comm, [sent: ^query]} = Btd.stream(comm, pmpp)
      [sent_packet] = comm.transport.sent

      assert {:ok, %PMPP{address: @address, control: :information_poll, body: ntcip_body}, ""} =
               PMPP.decode(sent_packet)

      assert {:ok, %NTCIP{group: @group, pdu_type: :set, request_id: 0, message: ^ntcip_message}} =
               NTCIP.decode(ntcip_body)
    end
  end

  describe "stream/2" do
    test "reconnects if the transport closes the connection" do
      comm =
        Btd.new(
          FakeTransport.new(),
          group: @group,
          address: @address,
          intersection_id: @intersection_id
        )

      {:ok, comm} = Btd.connect(comm)
      {:ok, comm, []} = Btd.stream(comm, :close)
      assert comm.transport.connect_count == 2
    end
  end
end
