# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

# Configures the endpoint
config :tablespoon, TablespoonWeb.Endpoint,
  http: [port: 4000],
  url: [host: "localhost", port: 4000],
  secret_key_base: "g+uRKkw3yrnh15jhEantHUsmWWUnzwdFRHSX2K+a+5I7rilZeyk7Ptv9kUBwqKAE",
  render_errors: [view: TablespoonWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: Tablespoon.PubSub, adapter: Phoenix.PubSub.PG2]

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

config :tablespoon,
  configs: "priv/intersections.json",
  fuse_options: {
    # tolerate 5 failures in 5 minutes
    {:standard, 5, 300_000},
    # reset the fuse after 60 seconds
    {:reset, 60_000}
  }

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
