defmodule Tablespoon.Protocol.TransitmasterXmlTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Tablespoon.Protocol.TransitmasterXml
  import Tablespoon.PropertyHelpers

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

  describe "encode/decode" do
    property "encode/decode are parallel operations" do
      check all(
              message <- gen_message(),
              extra <- binary()
            ) do
        encoded = TransitmasterXml.encode(message)
        binary = IO.iodata_to_binary([encoded, extra])
        assert {{:ok, ^message, ^extra}, ^binary} = {TransitmasterXml.decode(binary), binary}
      end
    end
  end

  describe "decode/1" do
    test "can decode a sample message" do
      assert {:ok, tm, "extra"} = TransitmasterXml.decode(@data <> "extra")

      assert tm == %TransitmasterXml{
               id: "00FCE914-739B-4981-9651-CA5480C8D4C3",
               type: :checkout,
               event_time:
                 DateTime.to_unix(
                   DateTime.from_naive!(~N[2018-10-12T20:59:31], "Etc/UTC"),
                   :native
                 ),
               event_id: 1,
               vehicle_id: "0002",
               vehicle_latitude: 42.3407551,
               vehicle_longitude: -71.0637025
             }
    end

    test "invalid packets are rejected" do
      assert {:error, :invalid, ""} = TransitmasterXml.decode("invalid")

      invalid_date_time =
        "TMTSPDATAHEADER000684<?xml version=\"1.0\"?>\r\n<TSP_CHECKOUTMESSAGE>\r\n<GUID>00FCE914-739B-4981-9651-CA5480C8D4C3</GUID>\r\n<TRAFFIC_SIGNAL_EVENT_ID>1</TRAFFIC_SIGNAL_EVENT_ID>\r\n<EVENT_TIME>2018-10Y12T20:59:31.000Z</EVENT_TIME>\r\n<EVENT_GEO_NODE_ABBR>CamGorWB</EVENT_GEO_NODE_ABBR>\r\n<VEHICLE_ID>0002</VEHICLE_ID>\r\n<ROUTE_ABBR>Unknown</ROUTE_ABBR>\r\n<APPROACH_DIRECTION>235</APPROACH_DIRECTION>\r\n<NODE_LATITUDE>42.3526278</NODE_LATITUDE>  \n<NODE_LONGITUDE>-71.1401139</NODE_LONGITUDE>\r\n<VEHICLE_LATITUDE>42.3407551</VEHICLE_LATITUDE>\r\n<VEHICLE_LONGITUDE>-71.063725</VEHICLE_LONGITUDE>\r\n<DEVIATION_FROM_SCHEDULE>0</DEVIATION_FROM_SCHEDULE>\r\n<DISTANCE>305</DISTANCE>\r\n<BUS_LOAD>0</BUS_LOAD>\r\n</TSP_CHECKOUTMESSAGE>\r\n"

      assert {:error, :invalid, ""} = TransitmasterXml.decode(invalid_date_time)

      invalid_version =
        "TMTSPDATAHEADER000685<?xml version=pt(1.0\"?>\r\n<TSP_CHECKOUTMESSAE>\r\n<GUID>00FCE914-739B-4981-9651-CA5480C8DC3</GUID>\r\n<TRAFFIC_SIGNAL_EVENT_ID>1</TRAFFIC_SIGNAL_EVENT_ID>\r\n<EVENT_TIME>2018-10-12T20:59:31.000Z</EVENT_TIME>\r\n<EVENT_GEO_NODE_ABBR>CamGorWB</EVENT_GEO_NODE_ABB>\r\n<Vz HICL__ID>0002</VEHICLE_ID>\r\n<ROUTE_ABBR>Unknown</ROUTE_ABBR>\r\n<APPROACH_DIRECTION>235</APPROACH_DIRECTION>\r\n<NODE_LATITUDE>42.3526278</NODE_LATITUDE>\r\n<NODE_LONGITUDE>-71.1401139</NODE_LONGITUDE>\r\n<VEHICLE_LATITUDE>42.3407551</VEHICLE_LATITUDE>\r\n<VEHICLE_LONGnjTUDE>-71.0637025</VEHICLE_LONGITUDE>\r\n<DEVIATION_FROM_SCHEDULE>0</DEVIATION_FROM_SCHEDULE>\r\n<DISTANCE>305</DISTANCE>\r\n<BUS_LOAD>0</BUS_LOAD>\r\n</TSP_CHECKOUTMESSAGE>\r\n"

      assert {:error, :invalid, ""} = TransitmasterXml.decode(invalid_version)
    end

    property "dropping data returns :too_short error" do
      max_slice = byte_size(@data) - 1

      check all(slice_size <- integer(1..max_slice)) do
        data = Kernel.binary_part(@data, 0, slice_size)
        assert {:error, :too_short, ^data} = TransitmasterXml.decode(data)
      end
    end

    property "does not crash" do
      check all(packet <- modified_packet(@data, string(:ascii, min_length: 0, max_length: 3))) do
        case TransitmasterXml.decode(packet) do
          {:ok, %TransitmasterXml{}, bin} when is_binary(bin) ->
            :ok

          {:error, _, bin} when is_binary(bin) ->
            :ok
        end
      end
    end
  end

  defp gen_message do
    gen all(
          id <- string(:alphanumeric),
          type <- one_of([constant(:checkin), constant(:checkout)]),
          event_time_seconds <- non_neg_integer(),
          event_id <- non_neg_integer(),
          vehicle_id <- string(:alphanumeric),
          latitude <- one_of([constant(nil), float()]),
          longitude <- one_of([constant(nil), float()])
        ) do
      %TransitmasterXml{
        id: id,
        type: type,
        event_time: System.convert_time_unit(event_time_seconds, :second, :native),
        event_id: event_id,
        vehicle_id: vehicle_id,
        vehicle_latitude: latitude,
        vehicle_longitude: longitude
      }
    end
  end

  defp non_neg_integer do
    sized(fn size ->
      integer(0..size)
    end)
  end
end
