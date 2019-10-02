use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tablespoon, TablespoonWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# don't load intersection configuration
config :tablespoon,
  configs: nil

# Configure StreamData to use more rounds in CI
if System.get_env("CI") do
  max_runs =
    case System.get_env("STREAM_DATA_MAX_RUNS") do
      nil -> 500
      value -> String.to_integer(value)
    end

  config :stream_data, max_runs: max_runs
end
