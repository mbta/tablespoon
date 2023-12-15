import Config

# Always start the server
config :tablespoon, TablespoonWeb.Endpoint, server: true

config :logger, backends: [:console]

config :logger, level: :info

config :logger, :console,
  format: "[$level] $metadata$message\n",
  level: :warning

config :ehmon, :report_mf, {:ehmon, :info_report}
