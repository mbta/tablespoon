defmodule Tablespoon.QueryTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Tablespoon.Query

  describe "new/1" do
    test "sets received_at_mono" do
      query =
        new(
          id: "id",
          type: :request,
          vehicle_id: "veh",
          intersection_alias: "int",
          approach: :west,
          event_time: System.system_time()
        )

      assert is_integer(query.received_at_mono)
    end

    test "accepts a passed in received_at" do
      query =
        new(
          id: "id",
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
end
