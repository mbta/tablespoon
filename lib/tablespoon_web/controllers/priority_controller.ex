defmodule TablespoonWeb.PriorityController do
  @moduledoc """
  Receive priority queries over HTTP.

  Requests and cancels both come into the /priority endpoint as GET requests.

  Requests have the following params:
  - "messageid" => used to detect duplicates
  - "type" => "request"
  - "intersection" => intersection alias,
  - "approach" => "1" for North, "2" for East, &c
  - "vehicle" => vehicle ID
  - "t" => Epoch timestamp (in seconds) when the request was made

  Cancels have the following params:
  - "messageid" => used to detect duplicates
  - "type" => "cancel"
  - "intersection" => intersection alias,
  - "approach" => "1" for North, "2" for East, &c
  - "vehicle" => vehicle ID
  - "t" => Epoch timestamp (in seconds) when the request was made
  - "ref" => could be used to reference the Request, but currently a static value
  """
  use TablespoonWeb, :controller
  alias Tablespoon.Intersection

  def index(conn, params) do
    params
    |> query_from_params
    |> Intersection.send_query()

    send_resp(conn, 200, "")
  end

  @doc "Build a Tablespoon.Query from the given params"
  def query_from_params(params) do
    # include parsing time in the total time
    received_at_mono = System.monotonic_time()

    %{
      "messageid" => id,
      "type" => type_binary,
      "intersection" => intersection_alias,
      "approach" => approach_binary,
      "vehicle" => vehicle_id,
      "t" => event_time_binary
      # ref is ignored
    } = params

    type = type(type_binary)
    approach = approach(approach_binary)
    event_time = event_time(event_time_binary)

    Tablespoon.Query.new(
      id: id,
      type: type,
      intersection_alias: intersection_alias,
      approach: approach,
      vehicle_id: vehicle_id,
      event_time: event_time,
      received_at_mono: received_at_mono
    )
  end

  defp type("request"), do: :request
  defp type("cancel"), do: :cancel

  defp approach("1"), do: :north
  defp approach("2"), do: :east
  defp approach("3"), do: :south
  defp approach("4"), do: :west

  defp event_time(binary) do
    binary
    |> String.to_integer()
    |> System.convert_time_unit(:second, :native)
  end
end
