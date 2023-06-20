defmodule TablespoonTcp.HandlerTest do
  @moduledoc false
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias Tablespoon.Protocol.TransitmasterXml
  alias Tablespoon.Query
  alias TablespoonTcp.Handler

  @data ~s(TMTSPDATAHEADER000684<?xml version=\"1.0\"?>\r
<TSP_CHECKOUTMESSAGE>\r
<GUID>00FCE914-739B-4981-9651-CA5480C8D4C3</GUID>\r
<TRAFFIC_SIGNAL_EVENT_ID>1</TRAFFIC_SIGNAL_EVENT_ID>\r
<EVENT_TIME>2018-10-12T20:59:31.000Z</EVENT_TIME>\r
<EVENT_GEO_NODE_ABBR>CamGorWB</EVENT_GEO_NODE_ABBR>\r
<VEHICLE_ID>0002</VEHICLE_ID>\r
<ROUTE_ABBR>Unknown</ROUTE_ABBR>\r
<APPROACH_DIRECTION>235</APPROACH_DIRECTION>\r
<NODE_LATITUDE>42.3526278</NODE_LATITUDE>\r
<NODE_LONGITUDE>-71.1401139</NODE_LONGITUDE>\r
<VEHICLE_LATITUDE>42.3407551</VEHICLE_LATITUDE>\r
<VEHICLE_LONGITUDE>-71.0637025</VEHICLE_LONGITUDE>\r
<DEVIATION_FROM_SCHEDULE>0</DEVIATION_FROM_SCHEDULE>\r
<DISTANCE>305</DISTANCE>\r
<BUS_LOAD>0</BUS_LOAD>\r
</TSP_CHECKOUTMESSAGE>\r
)

  @invalid_date_time ~s(TMTSPDATAHEADER000684<?xml version=\"1.0\"?>\r
<TSP_CHECKOUTMESSAGE>\r
<GUID>00FCE914-739B-4981-9651-CA5480C8D4C3</GUID>\r
<TRAFFIC_SIGNAL_EVENT_ID>1</TRAFFIC_SIGNAL_EVENT_ID>\r
<EVENT_TIME>2018-10-12Y20:59:31.000Z</EVENT_TIME>\r
<EVENT_GEO_NODE_ABBR>CamGorWB</EVENT_GEO_NODE_ABBR>\r
<VEHICLE_ID>0002</VEHICLE_ID>\r
<ROUTE_ABBR>Unknown</ROUTE_ABBR>\r
<APPROACH_DIRECTION>235</APPROACH_DIRECTION>\r
<NODE_LATITUDE>42.3526278</NODE_LATITUDE>\r
<NODE_LONGITUDE>-71.1401139</NODE_LONGITUDE>\r
<VEHICLE_LATITUDE>42.3407551</VEHICLE_LATITUDE>\r
<VEHICLE_LONGITUDE>-71.0637025</VEHICLE_LONGITUDE>\r
<DEVIATION_FROM_SCHEDULE>0</DEVIATION_FROM_SCHEDULE>\r
<DISTANCE>305</DISTANCE>\r
<BUS_LOAD>0</BUS_LOAD>\r
</TSP_CHECKOUTMESSAGE>\r
)

  setup do
    handler_options = %{
      handler_module: Handler,
      query_module: __MODULE__
    }

    Process.register(self(), __MODULE__)

    {:ok, pid} =
      ThousandIsland.start_link(
        port: 0,
        handler_module: Handler,
        handler_options: handler_options
      )

    {:ok, %{port: port}} = ThousandIsland.listener_info(pid)
    {:ok, %{pid: pid, port: port}}
  end

  describe "handle_info/2" do
    test "handles a whole packet of data", %{port: port} do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [])
      :ok = :gen_tcp.send(socket, @data)
      assert_receive {:query, %Query{intersection_alias: "99999999", approach: :north}}

      # connection is still open
      refute_receive {:tcp_closed, ^socket}
    end

    test "handles slowly receiving a packet of data", %{port: port} do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [])

      for byte <- String.split(@data, "") do
        refute_received {:query, _}
        :ok = :gen_tcp.send(socket, byte)
      end

      assert_receive {:query, %Query{}}
    end

    test "closes the connection if the packet is not valid", %{port: port} do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", port, nodelay: true)

      :ok = :gen_tcp.send(socket, "INVALID PACKET")
      assert_receive {:tcp_closed, ^socket}
    end

    test "logs a message if the packet has an XML error", %{port: port} do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", port, nodelay: true)

      log =
        capture_log([level: :error], fn ->
          :ok = :gen_tcp.send(socket, @invalid_date_time)
          assert_receive {:tcp_closed, ^socket}
        end)

      assert log =~ "error while parsing"
      assert log =~ "peername={127, 0, 0, 1}"
    end
  end

  describe "as_query/1" do
    test "converts a TransitmasterXml struct into a Query" do
      tm = %TransitmasterXml{
        id: "12345",
        type: :checkout,
        event_time: 1000,
        event_id: 1,
        vehicle_id: "8765",
        vehicle_latitude: 1.0,
        vehicle_longitude: -1.0
      }

      q = Handler.as_query(tm)
      assert q.id == "12345"
      assert q.type == :cancel
      assert q.event_time == 1000
      assert q.intersection_alias == "99999999"
      assert q.approach == :north
      assert q.vehicle_latitude == 1.0
      assert q.vehicle_longitude == -1.0
    end
  end

  def send_query(query) do
    send(__MODULE__, {:query, query})
  end
end
