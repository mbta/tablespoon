defmodule Tablespoon.Intersection.Config do
  @moduledoc """
  Configuration options for Intersections.
  """
  defstruct [
    :id,
    :name,
    :alias,
    :active?
  ]

  @doc "Parse a JSON object into a Config"
  def from_json(map) do
    %{
      "id" => id,
      "name" => name,
      "intersectionAlias" => intersection_alias,
      "active" => active?
    } = map

    %__MODULE__{id: id, name: name, alias: intersection_alias, active?: active?}
  end
end
