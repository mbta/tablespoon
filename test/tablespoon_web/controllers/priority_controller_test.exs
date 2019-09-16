defmodule TablespoonWeb.Controllers.PriorityTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  import TablespoonWeb.Controllers.Priority

  describe "query_from_params/1" do
    property "params are parsed into a query" do
      check all(params <- gen_params()) do
        actual = query_from_params(params)
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
