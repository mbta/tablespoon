defmodule Tablespoon.Query do
  @moduledoc """
  A message from a vehicle to either request or cancel priority.
  """
  @enforce_keys [
    :id,
    :type,
    :vehicle_id,
    :intersection_alias,
    :approach,
    :event_time,
    :received_at_mono
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: id,
          type: query_type,
          vehicle_id: vehicle_id,
          intersection_alias: intersection_alias,
          approach: approach,
          event_time: non_neg_integer,
          received_at_mono: integer
        }
  @type id :: binary
  @type query_type :: :request | :cancel
  @type vehicle_id :: binary
  @type intersection_alias :: binary
  @type approach :: :north | :east | :south | :west

  @doc "Create a new Query"
  @spec new(Keyword.t()) :: t
  def new(opts) do
    opts = Map.new(opts)
    opts = Map.put_new_lazy(opts, :received_at_mono, &System.monotonic_time/0)
    struct!(__MODULE__, opts)
  end
end
