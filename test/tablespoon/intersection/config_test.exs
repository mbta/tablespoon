defmodule Tablespoon.Intersection.ConfigTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Tablespoon.Communicator.Modem
  alias Tablespoon.Intersection.Config
  alias Tablespoon.Transport.FakeModem
  import Config

  @sample_json %{
    "id" => 1,
    "name" => "TSP Intersection",
    "communicationType" => "Modem",
    "intersectionAlias" => "BOS123",
    "active" => true,
    "monitoringInterval" => 240,
    "startTime" => "07:00:00",
    "endTime" => "00:00:00"
  }

  describe "from_json" do
    test "returns a %Config{}" do
      expected = %Config{
        id: 1,
        name: "TSP Intersection",
        alias: "BOS123",
        active?: true,
        warning_timeout_ms: 240 * 60 * 1000,
        warning_not_before_time: {7, 0, 0},
        warning_not_after_time: {24, 0, 0},
        communicator: Modem.new(FakeModem.new())
      }

      actual = from_json(@sample_json)
      assert expected == actual
    end
  end
end
