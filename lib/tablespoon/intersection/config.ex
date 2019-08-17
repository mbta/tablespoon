defmodule Tablespoon.Intersection.Config do
  @moduledoc """
  Configuration options for Intersections.
  """
  @enforce_keys [:id, :alias]
  defstruct [
    :id,
    :alias,
    name: nil,
    active?: true,
    warning_timeout_ms: :infinity,
    warning_not_before_time: {24, 0, 0},
    warning_not_after_time: {0, 0, 0}
  ]

  @doc "Parse a JSON object into a Config"
  def from_json(map) do
    %{
      "id" => id,
      "name" => name,
      "intersectionAlias" => intersection_alias,
      "active" => active?,
      "monitoringInterval" => warning_timeout_minute,
      "startTime" => warning_not_before_binary,
      "endTime" => warning_not_after_binary
    } = map

    warning_timeout_ms = warning_timeout_minute * 60_000
    warning_not_before = time(warning_not_before_binary)

    warning_not_after =
      case time(warning_not_after_binary) do
        {0, 0, 0} -> {24, 0, 0}
        time -> time
      end

    %__MODULE__{
      id: id,
      name: name,
      alias: intersection_alias,
      active?: active?,
      warning_timeout_ms: warning_timeout_ms,
      warning_not_before_time: warning_not_before,
      warning_not_after_time: warning_not_after
    }
  end

  defp time(<<hour_binary::binary-2, ?:, minute_binary::binary-2, ?:, second_binary::binary-2>>) do
    {
      String.to_integer(hour_binary),
      String.to_integer(minute_binary),
      String.to_integer(second_binary)
    }
  end
end
