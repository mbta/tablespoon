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

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# connection configuration for the different types of Communicators
config :tablespoon, Tablespoon.Communicator.Btd,
  transport: {Tablespoon.Transport.FakeBtd, []},
  group: "fake_group",
  address: 1

config :tablespoon, Tablespoon.Communicator.Modem, transport: {Tablespoon.Transport.FakeModem, []}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
