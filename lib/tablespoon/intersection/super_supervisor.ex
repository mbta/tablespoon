defmodule Tablespoon.Intersection.SuperSupervisor do
  @moduledoc """
  Supervisor for the registry and intersection supervisor.
  """
  use Supervisor

  def start_link(configs) do
    Supervisor.start_link(__MODULE__, configs)
  end

  def init(configs) do
    Supervisor.init(
      [
        {Registry, name: Tablespoon.Intersection.registry(), keys: :unique},
        {Tablespoon.Intersection.Supervisor, configs}
      ],
      strategy: :one_for_all
    )
  end
end
