defmodule Tablespoon.Intersection.Supervisor do
  @moduledoc """
  Supervisor for all the Intersection processes
  """
  def start_link(configs) do
    child_specs =
      for config <- configs do
        {Tablespoon.Intersection, config}
      end

    Supervisor.start_link(child_specs, strategy: :one_for_one)
  end
end
