opts =
  if System.get_env("CI") do
    [timeout: 600_000]
  else
    []
  end

ExUnit.start(opts)
