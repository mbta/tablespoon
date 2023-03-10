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

  # overrides Logster 1.1s default of using :error for 500s and :warn for 400s
  plug Logster.Plugs.ChangeLogLevel, to: :info

  def index(conn, params) do
    case query_from_params(params) do
      {:ok, q} ->
        Intersection.send_query(q)
        send_resp(conn, 200, "")

      :error ->
        send_resp(conn, 400, "invalid request")
    end
  end

  @doc "Build a Tablespoon.Query from the given params"
  @spec query_from_params(map) :: {:ok, Tablespoon.Query.t()} | :error
  def query_from_params(params) do
    # include parsing time in the total time
    received_at_mono = System.monotonic_time()

    with %{
           "messageid" => id,
           "type" => type_binary,
           "intersection" => intersection_alias,
           "approach" => approach_binary,
           "vehicle" => vehicle_id,
           "t" => event_time_binary
           # ref is ignored
         } <- params,
         {:ok, type} <- type(type_binary),
         {:ok, approach} <- approach(approach_binary),
         {:ok, event_time} <- event_time(event_time_binary) do
      q =
        Tablespoon.Query.new(
          id: id,
          source: __MODULE__,
          type: type,
          intersection_alias: intersection_alias,
          approach: approach,
          vehicle_id: vehicle_id,
          event_time: event_time,
          received_at_mono: received_at_mono
        )

      {:ok, q}
    else
      m when is_map(m) ->
        :error

      error ->
        error
    end
  end

  defp type("request"), do: {:ok, :request}
  defp type("cancel"), do: {:ok, :cancel}
  defp type(_), do: :error

  defp approach("1"), do: {:ok, :north}
  defp approach("2"), do: {:ok, :east}
  defp approach("3"), do: {:ok, :south}
  defp approach("4"), do: {:ok, :west}
  defp approach(_), do: :error

  defp event_time(binary) do
    case Integer.parse(binary) do
      {seconds, ""} ->
        {:ok, System.convert_time_unit(seconds, :second, :native)}

      _ ->
        :error
    end
  end
end
