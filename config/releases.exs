import Config

intersections_binary =
  if bin = System.get_env("INTERSECTIONS_JSON") do
    bin
  else
    case File.read(Application.app_dir(:tablespoon, "priv/intersections.json")) do
      {:ok, bin} ->
        bin

      {:error, e} ->
        IO.puts("[warn] unable to read intersections data on startup: #{inspect(e)}")
        nil
    end
  end

config :tablespoon,
  configs: intersections_binary
