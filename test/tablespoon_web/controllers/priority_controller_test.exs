defmodule TablespoonWeb.PriorityControllerTest do
  @moduledoc false
  use TablespoonWeb.ConnCase, async: true
  use ExUnitProperties
  import ExUnit.CaptureLog
  import TablespoonWeb.Router.Helpers
  import TablespoonWeb.PriorityController

  describe "index" do
    test "invalid requests do not log an error", %{conn: conn} do
      log =
        capture_log(fn ->
          conn = get(conn, priority_path(conn, :index))
          assert conn.status == 400
        end)

      assert log == ""
    end
  end

  describe "query_from_params/1" do
    property "params are parsed into a query" do
      check all(params <- gen_params()) do
        {:ok, actual} = query_from_params(params)
        assert %Tablespoon.Query{} = actual
        assert actual.id == params["messageid"]
        assert actual.type == String.to_existing_atom(params["type"])
        assert actual.intersection_alias == params["intersection"]
        assert actual.vehicle_id == params["vehicle"]

        assert Integer.to_string(System.convert_time_unit(actual.event_time, :native, :second)) ==
                 params["t"]
      end
    end
  end

  defp gen_params do
    time = System.system_time(:second)
    min_time = div(time, 10)
    max_time = time * 10

    StreamData.fixed_map(%{
      "messageid" => StreamData.binary(min_length: 1),
      "type" =>
        StreamData.one_of([StreamData.constant("request"), StreamData.constant("cancel")]),
      "intersection" => StreamData.binary(min_length: 1),
      "approach" => StreamData.map(StreamData.integer(1..4), &Integer.to_string/1),
      "vehicle" => StreamData.binary(min_length: 1),
      "t" => StreamData.map(StreamData.integer(min_time..max_time), &Integer.to_string/1)
    })
  end
end
