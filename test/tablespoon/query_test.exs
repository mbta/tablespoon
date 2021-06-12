defmodule Tablespoon.QueryTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Tablespoon.Query

  setup do
    query =
      new(
        id: "id",
        source: :testing,
        type: :request,
        vehicle_id: "veh",
        intersection_alias: "int",
        approach: :west,
        event_time: System.system_time()
      )

    {:ok, query: query}
  end

  describe "new/1" do
    test "sets received_at_mono", %{query: query} do
      assert is_integer(query.received_at_mono)
    end

    test "accepts a passed in received_at" do
      query =
        new(
          id: "id",
          source: :testing,
          type: :request,
          vehicle_id: "veh",
          intersection_alias: "int",
          approach: :west,
          event_time: System.system_time(),
          received_at_mono: -5
        )

      assert query.received_at_mono == -5
    end

    test "will not build a struct with missing values" do
      assert_raise ArgumentError, fn -> new([]) end
    end
  end

  describe "processing_time/2" do
    test "returns the amount of time processing took in the given unit", %{query: query} do
      assert processing_time(query, :second) == 0
      assert processing_time(query, :nanosecond) > 0
    end
  end
end
