defmodule TablespoonWeb.IntersectionsViewTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  import TablespoonWeb.IntersectionsView

  describe "ms_to_minute" do
    property "converts a number of millieconds into a number of minutes" do
      check all(ms <- non_negative_integer()) do
        seconds = System.convert_time_unit(ms, :millisecond, :second)
        minutes = div(seconds, 60)
        assert ms_to_minute(ms) == minutes
      end
    end

    test "converts :infinity to nil" do
      assert ms_to_minute(:infinity) == nil
    end
  end

  describe "friendly_time/1" do
    test "converts an Erlang time tuple to H:MM" do
      assert IO.iodata_to_binary(friendly_time({1, 2, 3})) == "1:02"
    end

    test "converts an Erlang time tuple to HH:MM" do
      assert IO.iodata_to_binary(friendly_time({11, 22, 33})) == "11:22"
    end

    test "handles midnight represented as {24, 0, 0}" do
      assert IO.iodata_to_binary(friendly_time({24, 0, 0})) == "24:00"
    end
  end

  defp non_negative_integer do
    one_of([
      positive_integer(),
      constant(0)
    ])
  end
end
