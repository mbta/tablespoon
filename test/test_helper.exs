opts = [
  # their test server is down at the moment
  exclude: :rebex
]

opts =
  if System.get_env("CI") do
    [timeout: 600_000] ++ opts
  else
    opts
  end

ExUnit.start(opts)
