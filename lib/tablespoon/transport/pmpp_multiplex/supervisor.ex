defmodule Tablespoon.Transport.PMPPMultiplex.Supervisor do
  @moduledoc """
  Supervisor for the various servers needed for PMPP multiplexing.

  - DynamicSupervisor: supervisor to the Child servers
  - Registry: for mapping the Transport object to a given Child of the DynamicSupervisor
  - Child: a GenServer responsible for sending the PMPP messages and sending back responses
  """
  use Supervisor
  alias Tablespoon.Transport.PMPPMultiplex

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    Supervisor.init(
      [
        {Registry, keys: :unique, name: PMPPMultiplex.registry()},
        {DynamicSupervisor, strategy: :one_for_one, name: PMPPMultiplex.dynamic_supervisor()}
      ],
      strategy: :one_for_all
    )
  end
end
