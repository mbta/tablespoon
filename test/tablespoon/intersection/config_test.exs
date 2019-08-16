defmodule Tablespoon.Intersection.ConfigTest do
  use ExUnit.Case, async: true
  alias Tablespoon.Intersection.Config
  import Config

  @sample_json %{
    "id" => 1,
    "name" => "TSP Intersection",
    "intersectionAlias" => "BOS123",
    "active" => true
  }

  describe "from_json" do
    test "returns a %Config{}" do
      expected = %Config{id: 1, name: "TSP Intersection", alias: "BOS123", active?: true}
      actual = from_json(@sample_json)
      assert expected == actual
    end
  end
end
