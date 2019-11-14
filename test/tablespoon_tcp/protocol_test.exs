defmodule TablespoonTcp.ProtocolTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Tablespoon.Protocol.TransitmasterXml
  alias TablespoonTcp.Protocol
  import Protocol

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

  describe "handle_info/2" do
    test "handles TCP data" do
      socket = make_ref()
      state = %Protocol{socket: socket}
      assert handle_info({:tcp, socket, "T"}, state) == {:noreply, %{state | buffer: "T"}}
    end

    test "ignores TCP data from the wrong socket" do
      socket = make_ref()
      state = %Protocol{socket: socket}
      assert_raise FunctionClauseError, fn -> handle_info({:tcp, make_ref(), "T"}, state) end
    end

    test "handles TCP close" do
      socket = make_ref()
      state = %Protocol{socket: socket}
      assert handle_info({:tcp_closed, socket}, state) == {:stop, :normal, state}
    end

    test "ignores TCP close from the wrong socket" do
      socket = make_ref()
      state = %Protocol{socket: socket}
      assert_raise FunctionClauseError, fn -> handle_info({:tcp_closed, make_ref()}, state) end
    end
  end

  describe "handle_buffer/1" do
    test "returns a list of queries and a reply" do
      state = %{buffer: @data}
      assert {[:existing, query], {:noreply, %{buffer: ""}}} = handle_buffer({[:existing], state})
    end

    test "returns more queries if they're in the buffer" do
      buffer = @data <> @data <> "TM"
      state = %{buffer: buffer}
      assert {[_, _], {:noreply, %{buffer: "TM"}}} = handle_buffer({[], state})
    end

    @tag :capture_log
    test "stops if there's an error" do
      state = %{buffer: "invalid"}
      assert {[], {:stop, :normal, _}} = handle_buffer({[], state})
    end
  end

  describe "as_query/1" do
    test "converts a TransitmasterXml struct into a Query" do
      tm = %TransitmasterXml{
        id: "12345",
        type: :checkout,
        event_time: 1000,
        event_id: 1,
        vehicle_id: "8765"
      }

      q = as_query(tm)
      assert q.id == "12345"
      assert q.type == :cancel
      assert q.event_time == 1000
      assert q.intersection_alias == "99999999"
      assert q.approach == :north
    end
  end
end
