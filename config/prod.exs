import Config

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
  format: "[$level] $metadata$message",
  metadata: [:request_id],
  level: :info

config :ehmon, :report_mf, {:ehmon, :info_report}
