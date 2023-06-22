defmodule TablespoonTcp.Handler do
  @moduledoc """
  ThousandIsland implementation for sending Transitmaster TSP queries
  """
  use ThousandIsland.Handler
  alias Tablespoon.Intersection
  alias Tablespoon.Protocol.TransitmasterXml
  require Logger

  @type t :: %__MODULE__{
          socket: port,
          buffer: binary,
          query_module: atom
        }
  defstruct [:socket, buffer: "", query_module: Intersection]

  @impl ThousandIsland.Handler
  def handle_connection(socket, state) do
    module_state = %__MODULE__{socket: socket}

    module_state = %{
      module_state
      | query_module: Map.get(state, :query_module, module_state.query_module)
    }

    state = Map.put(state, __MODULE__, module_state)
    {:continue, state}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        data,
        socket,
        %{__MODULE__ => %{socket: socket, buffer: buffer} = module_state} = state
      ) do
    buffer = buffer <> data
    module_state = %{module_state | buffer: buffer}

    {queries, {reply, module_state}} = handle_buffer({[], module_state})
    :ok = Enum.each(queries, &module_state.query_module.send_query/1)

    state = %{state | __MODULE__ => module_state}
    {reply, state}
  end

  @spec handle_buffer({[Tablespoon.Query.t()], t()}) ::
          {[Tablespoon.Query.t()], ThousandIsland.Handler.handler_result()}
  def handle_buffer(acc)

  def handle_buffer({queries, %{buffer: ""} = state}) do
    {Enum.reverse(queries), {:continue, state}}
  end

  def handle_buffer({queries, %{buffer: buffer} = state}) do
    buffer
    |> TransitmasterXml.decode()
    |> handle_decoded_buffer(queries, state)
  end

  defp handle_decoded_buffer({:ok, tm, buffer}, queries, state) do
    q = as_query(tm)
    queries = [q | queries]

    state = %{state | buffer: buffer}
    handle_buffer({queries, state})
  end

  defp handle_decoded_buffer({:error, :too_short, buffer}, queries, state) do
    state = %{state | buffer: buffer}
    {Enum.reverse(queries), {:continue, state}}
  end

  defp handle_decoded_buffer({:error, :ignore, _buffer}, queries, state) do
    {Enum.reverse(queries), {:close, state}}
  end

  defp handle_decoded_buffer({:error, error, _buffer}, queries, state) do
    peername = ThousandIsland.Socket.peer_info(state.socket).address

    _ =
      Logger.error(fn ->
        "#{__MODULE__} error while parsing socket=#{inspect(state.socket.socket)} peername=#{inspect(peername)} error=#{inspect(error)} buffer=#{inspect(state.buffer, limit: 2048)}"
      end)

    {Enum.reverse(queries), {:close, state}}
  end

  @spec as_query(TransitmasterXml.t()) :: Tablespoon.Query.t()
  def as_query(tm) do
    type =
      case tm.type do
        :checkin -> :request
        :checkout -> :cancel
      end

    {intersection_alias, approach} = alias_approach(tm.event_id)

    Tablespoon.Query.new(
      id: tm.id,
      type: type,
      intersection_alias: intersection_alias,
      approach: approach,
      vehicle_id: tm.vehicle_id,
      event_time: tm.event_time,
      vehicle_latitude: tm.vehicle_latitude,
      vehicle_longitude: tm.vehicle_longitude
    )
  end

  defp alias_approach(event_id) do
    mapping =
      Application.get_env(:tablespoon, TablespoonTcp.Listener)[
        :event_id_to_intersection_direction
      ]

    case Map.fetch(mapping, event_id) do
      {:ok, alias_approach} ->
        alias_approach

      :error ->
        _ =
          Logger.warn(fn ->
            "#{__MODULE__} invalid Transitmaster event ID event_id=#{event_id}"
          end)

        {"invalid", :north}
    end
  end
end
