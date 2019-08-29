use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tablespoon, TablespoonWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Configure StreamData to use more rounds in CI
if System.get_env("CI") do
  config :stream_data, max_runs: 500
end
