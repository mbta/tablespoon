defmodule Tablespoon.IntersectionTest do
  use ExUnit.Case
  alias Tablespoon.{Intersection, Intersection.Config, Query}
  import ExUnit.CaptureLog

  @alias "test_alias"
  @config %Config{
    id: "test_id",
    alias: @alias
  }

  setup do
    {:ok, _pid} = Intersection.start_link(@config)
    :ok
  end

  describe "send_query/1" do
    setup do
      log_level = Logger.level()

      on_exit(fn ->
        Logger.configure(level: log_level)
      end)

      Logger.configure(level: :info)
      :ok
    end

    test "logs the query" do
      query =
        Query.new(
          id: "test_query_id",
          type: :cancel,
          intersection_alias: @alias,
          approach: :south,
          vehicle_id: "vehicle_id",
          event_time: 0
        )

      log =
        capture_log(fn ->
          :ok = Intersection.send_query(query)
          :ok = Intersection.flush(@alias)
        end)

      assert log =~ "Query - id=test_id alias=test_alias"
      assert log =~ "type=cancel"
      assert log =~ "v_id=vehicle_id"
      assert log =~ "approach=south"
      assert log =~ "event_time=1970-01-01T00:00:00Z"
      assert log =~ "processing_time_us="
    end
  end
end
