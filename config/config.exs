# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
config :tablespoon, TablespoonWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [
    port: 4000,
    thousand_island_options: [
      handler_options: %{
        plug: {TablespoonWeb.Endpoint, []},
        handler_module: TablespoonWeb.InitialHandler,
        opts: %{
          http_1: [],
          http_2: [],
          websocket: []
        }
      }
    ]
  ],
  url: [host: "localhost", port: 4000],
  secret_key_base: "g+uRKkw3yrnh15jhEantHUsmWWUnzwdFRHSX2K+a+5I7rilZeyk7Ptv9kUBwqKAE",
  render_errors: [view: TablespoonWeb.ErrorView, accepts: ~w(json html)]

config :tablespoon, TablespoonTcp.Listener,
  server: true,
  port: 9006,
  event_id_to_intersection_direction: %{}

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Use tzdata for time zone info
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

intersections =
  case File.read("priv/intersections.json") do
    {:ok, data} -> data
    _ -> nil
  end

config :tablespoon,
  configs: intersections,
  fuse_options: {
    # tolerate 5 failures in 5 minutes
    {:standard, 5, 300_000},
    # reset the fuse after 60 seconds
    {:reset, 60_000}
  },
  time_zone: "America/New_York"

# connection configuration for the different types of Communicators
config :tablespoon, Tablespoon.Communicator.Btd,
  transport: {Tablespoon.Transport.FakeBtd, []},
  group: "fake_group"

config :tablespoon, Tablespoon.Communicator.Modem, transport: {Tablespoon.Transport.FakeModem, []}

config :tablespoon, Tablespoon.Communicator.ModemTcp,
  transport: {Tablespoon.Transport.FakeModem, []}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
