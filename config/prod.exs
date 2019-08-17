use Mix.Config

config :logger, backends: [{Logger.Backend.Splunk, :splunk}, :console]

config :logger, level: :info

config :logger, :console, level: :warn

config :logger, :splunk,
  host: {:system, "SPLUNK_HOST"},
  token: {:system, "SPLUNK_TOKEN"},
  format: "$dateT$time [$level]$levelpad $metadata$message",
  metadata: [:request_id]
