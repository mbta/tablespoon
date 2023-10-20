import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tablespoon, TablespoonWeb.Endpoint,
  http: [port: 4002],
  server: true

config :tablespoon, TablespoonTcp.Listener,
  server: false,
  event_id_to_intersection_direction: %{
    1 => {"99999999", :north}
  }

# Print only warnings and errors during test, but always evaluate the arguments
config :logger,
  level: :warning,
  always_evaluate_messages: true

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
