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
    "communicationType" => "ModemTcp",
    "intersectionAlias" => "BOS123",
    "active" => true,
    "monitoringInterval" => 240,
    "startTime" => "07:00:00",
    "endTime" => "00:00:00",
    "ipAddress" => "0.0.0.0",
    "port" => 0
  }

  describe "from_json" do
    test "returns a %Config{}" do
      expected = %Config{
        name: "TSP Intersection",
        alias: "BOS123",
        active?: true,
        warning_timeout_ms: 240 * 60 * 1000,
        warning_not_before_time: {7, 0, 0},
        warning_not_after_time: {24, 0, 0},
        communicator: Modem.new(FakeModem.new(), expect_ok?: false)
      }

      actual = from_json(@sample_json)
      assert expected == actual
    end
  end
end
