use Mix.Config

# Always start the server
config :tablespoon, TablespoonWeb.Endpoint, server: true

config :logger, backends: [{Logger.Backend.Splunk, :splunk}, :console]

config :logger, level: :info

config :logger, :console,
  format: "[$level] $metadata$message\n",
  level: :warn

config :logger, :splunk,
  host: {:system, "SPLUNK_HOST"},
  token: {:system, "SPLUNK_TOKEN"},
  format: "[$level]$levelpad $metadata$message",
  metadata: [:request_id],
  level: :info

import_config "prod.secret.exs"
