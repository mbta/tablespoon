defmodule Tablespoon.Intersection.Supervisor do
  @moduledoc """
  Supervisor for all the Intersection processes
  """
  use Supervisor

  def start_link(configs) do
    Supervisor.start_link(__MODULE__, configs)
  end

  @impl Supervisor
  def init(configs) do
    configs
    |> child_specs()
    |> Supervisor.init(strategy: :one_for_one)
  end

  def child_specs(configs) do
    for config <- configs, config.active? do
      {Tablespoon.Intersection, config: config}
    end
  end
end
