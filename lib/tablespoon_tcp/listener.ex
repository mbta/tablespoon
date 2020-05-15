defmodule TablespoonTcp.Listener do
  @moduledoc """
  Supervisor for the Ranch TCP listener.
  """
  require Logger

  def start_link(opts \\ config()) do
    children = children(opts)

    _ =
      unless children == [] do
        Logger.info(fn ->
          "Running #{__MODULE__} at :#{opts[:port]} (tcp)"
        end)
      end

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def child_spec([]) do
    %{
      id: __MODULE__,
      type: :supervisor,
      start: {__MODULE__, :start_link, []}
    }
  end

  defp config do
    Application.get_env(:tablespoon, __MODULE__)
  end

  def children(opts) do
    if opts[:server] do
      [
        # ranch_sup is already started by Cowboy
        listener(opts)
      ]
    else
      []
    end
  end

  defp listener(opts) do
    :ranch.child_spec(
      __MODULE__,
      100,
      :ranch_tcp,
      [port: opts[:port]],
      TablespoonTcp.Protocol,
      []
    )
  end
end
