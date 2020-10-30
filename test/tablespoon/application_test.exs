defmodule Tablespoon.ApplicationTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Tablespoon.Application

  doctest Tablespoon.Application

  describe "configs/1" do
    test "returns parsed JSON if present" do
      json = [
        %{
          "name" => "name",
          "intersectionAlias" => "alias",
          "communicationType" => "Btd",
          "intersectionId" => 0,
          "active" => false,
          "monitoringInterval" => 0,
          "startTime" => "00:00:00",
          "endTime" => "11:59:59"
        }
      ]

      assert [%Tablespoon.Intersection.Config{}] = configs(Jason.encode!(json))
    end

    test "returns nil if no data is provided" do
      assert configs(nil) == []
    end
  end
end
