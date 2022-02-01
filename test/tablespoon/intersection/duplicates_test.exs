defmodule Tablespoon.Intersection.DuplicatesTest do
  use ExUnit.Case

  alias Tablespoon.Intersection.Duplicates
  alias Tablespoon.Query

  describe "seen?" do
    test "returns true after it has seen the query" do
      {:ok, _pid} = Duplicates.start_link([])

      query =
        Query.new(
          id: "id",
          type: :request,
          intersection_alias: "alias",
          vehicle_id: "1234",
          approach: :north,
          event_time: System.system_time()
        )

      refute Duplicates.seen?(query)
      assert Duplicates.seen?(query)
    end

    test "returns false after the duplicates are expired" do
      {:ok, _pid} = Duplicates.start_link(scan_frequency: 0)

      query =
        Query.new(
          id: "id",
          type: :request,
          intersection_alias: "alias",
          vehicle_id: "1234",
          approach: :north,
          event_time: System.system_time()
        )

      refute Duplicates.seen?(query)
      Process.sleep(1)
      refute Duplicates.seen?(query)
    end
  end
end
