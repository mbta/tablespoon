defmodule Tablespoon.Intersection.Config do
  @moduledoc """
  Configuration options for Intersections.
  """

  alias Tablespoon.Communicator

  @type t :: %__MODULE__{
          alias: String.t(),
          communicator: Communicator.t(),
          name: String.t() | nil,
          active?: boolean,
          warning_timeout_ms: non_neg_integer | :infinity,
          warning_not_before_time: :calendar.time() | {24, 0, 0},
          warning_not_after_time: :calendar.time()
        }

  @enforce_keys [:alias, :communicator]
  defstruct @enforce_keys ++
              [
                name: nil,
                active?: true,
                warning_timeout_ms: :infinity,
                warning_not_before_time: {24, 0, 0},
                warning_not_after_time: {0, 0, 0}
              ]

  @doc "Parse a JSON object into a Config"
  def from_json(map) do
    %{
      "name" => name,
      "intersectionAlias" => intersection_alias,
      "active" => active?,
      "monitoringInterval" => warning_timeout_minute,
      "startTime" => warning_not_before_binary,
      "endTime" => warning_not_after_binary
    } = map

    warning_timeout_ms = warning_timeout_minute * 60_000
    warning_not_before = time(warning_not_before_binary)

    warning_not_after =
      case time(warning_not_after_binary) do
        {0, 0, 0} -> {24, 0, 0}
        time -> time
      end

    %__MODULE__{
      name: name,
      alias: intersection_alias,
      active?: active?,
      warning_timeout_ms: warning_timeout_ms,
      warning_not_before_time: warning_not_before,
      warning_not_after_time: warning_not_after,
      communicator: communicator(map)
    }
  end

  defp time(<<hour_binary::binary-2, ?:, minute_binary::binary-2, ?:, second_binary::binary-2>>) do
    {
      String.to_integer(hour_binary),
      String.to_integer(minute_binary),
      String.to_integer(second_binary)
    }
  end

  defp communicator(%{"communicationType" => "Btd", "intersectionId" => intersection_id}) do
    config = Application.get_env(:tablespoon, Communicator.Btd)
    {transport_config, config} = Keyword.pop(config, :transport)
    transport = transport(transport_config, [])
    config = Keyword.put(config, :intersection_id, intersection_id)

    Communicator.Btd.new(
      transport,
      config
    )
  end

  defp communicator(%{"communicationType" => "Modem"} = map) do
    config = Application.get_env(:tablespoon, Communicator.Modem)

    additional_opts = [
      host: Map.fetch!(map, "ipAddress"),
      port: Map.fetch!(map, "port"),
      username: Map.fetch!(map, "userName"),
      password: Map.fetch!(map, "password")
    ]

    transport = transport(config[:transport], additional_opts)

    Communicator.Modem.new(transport)
  end

  defp communicator(%{"communicationType" => "ModemTcp"} = map) do
    config = Application.get_env(:tablespoon, Communicator.ModemTcp)

    additional_opts = [
      host: Map.fetch!(map, "ipAddress"),
      port: Map.fetch!(map, "port")
    ]

    transport = transport(config[:transport], additional_opts)

    Communicator.Modem.new(transport, expect_ok?: false)
  end

  defp transport({transport, transport_opts}, additional_opts \\ []) do
    transport_opts =
      if Keyword.has_key?(transport_opts, :transport) do
        sub_transport = transport(transport_opts[:transport])
        Keyword.put(transport_opts, :transport, sub_transport)
      else
        transport_opts
      end

    transport.new(transport_opts ++ additional_opts)
  end
end
