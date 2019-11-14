defmodule Tablespoon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger
  alias Tablespoon.Intersection.Config

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      Tablespoon.Transport.PMPPMultiplex.Supervisor,
      Tablespoon.UniqueRangeCounter,
      {Tablespoon.Intersection.SuperSupervisor, configs()},
      TablespoonTcp.Listener,
      TablespoonWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tablespoon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TablespoonWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def configs do
    with path when is_binary(path) <- Application.get_env(:tablespoon, :configs),
         {:ok, data} <- File.read("priv/intersections.json") do
      data
      |> strip_bom()
      |> Jason.decode!()
      |> Enum.map(&Config.from_json/1)
    else
      {:error, e} ->
        _ =
          Logger.warn(fn ->
            "unable to read intersection configuration: #{inspect(e)}"
          end)

        []

      nil ->
        # quietly don't load intersections, for testing
        []
    end
  end

  @doc """
  Strip the (optional) Unicode Byte-Order-Mark from the given binary.

  ## Examples

      iex> strip_bom("1234")
      "1234"

      iex> strip_bom("\uFEFF5678")
      "5678"
  """
  def strip_bom(binary) do
    case :unicode.bom_to_encoding(binary) do
      {_, 0} ->
        binary

      {:utf8, length} ->
        binary_part(binary, length, byte_size(binary) - length)
    end
  end
end
