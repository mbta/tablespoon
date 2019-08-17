defmodule Tablespoon.Intersection do
  @moduledoc """
  Process representing a single intersection with TSP.
  """
  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: name(config))
  end

  def child_spec(config) do
    %{
      id: {__MODULE__, config.id},
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def name(config) do
    {:via, Registry, {registry(), config.alias}}
  end

  def registry, do: __MODULE__.Registry

  # Server callbacks
  @impl GenServer
  def init(config) do
    Logger.info(fn ->
      "started Intersection id=#{config.id} alias=#{config.alias}"
    end)

    {:ok, config}
  end
end
