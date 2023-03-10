defmodule Tablespoon.Query do
  @moduledoc """
  A message from a vehicle to either request or cancel priority.
  """
  @enforce_keys [
    :id,
    :source,
    :type,
    :vehicle_id,
    :intersection_alias,
    :approach,
    :event_time,
    :received_at_mono
  ]
  defstruct @enforce_keys ++ [:vehicle_latitude, :vehicle_longitude]

  @type t :: %__MODULE__{
          id: id,
          source: atom,
          type: query_type,
          vehicle_id: vehicle_id,
          vehicle_latitude: float | nil,
          vehicle_longitude: float | nil,
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
    opts = opts_as_map(opts)
    struct!(__MODULE__, opts)
  end

  @doc "Returns the amount of time taken to handle the Query, in the given time unit"
  @spec processing_time(t, :native | System.time_unit()) :: non_neg_integer
  def processing_time(%__MODULE__{} = q, time_unit) do
    diff = System.monotonic_time() - q.received_at_mono
    System.convert_time_unit(diff, :native, time_unit)
  end

  @doc "Create a new Query based on an existing query, with some updates"
  @spec update(t, Keyword.t()) :: t
  def update(%__MODULE__{} = query, opts) do
    opts = opts_as_map(opts)
    struct!(query, opts)
  end

  defp opts_as_map(opts) do
    opts = Map.new(opts)
    Map.put_new_lazy(opts, :received_at_mono, &System.monotonic_time/0)
  end
end
