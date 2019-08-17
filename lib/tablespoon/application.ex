defmodule Tablespoon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger
  alias Tablespoon.Intersection.Config

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {Registry, name: Tablespoon.Intersection.registry(), keys: :unique},
      {Tablespoon.Intersection.Supervisor, configs()},
      # Start the endpoint when the application starts
      TablespoonWeb.Endpoint
      # Starts a worker by calling: Tablespoon.Worker.start_link(arg)
      # {Tablespoon.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tablespoon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TablespoonWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def configs do
    case File.read("priv/intersections.json") do
      {:ok, data} ->
        data
        |> Jason.decode!()
        |> Enum.map(&Config.from_json/1)

      {:error, e} ->
        Logger.warn(fn ->
          "unable to read intersection configuration: #{inspect(e)}"
        end)

        []
    end
  end
end
