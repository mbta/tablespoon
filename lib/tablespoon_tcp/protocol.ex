defmodule TablespoonTcp.Protocol do
  @moduledoc """
  :ranch_protocol implementation for sending Transitmaster TSP queries
  """
  use GenServer
  @behaviour :ranch_protocol
  alias Tablespoon.Intersection
  alias Tablespoon.Protocol.TransitmasterXml
  require Logger

  @type t :: %__MODULE__{
          socket: port,
          buffer: binary
        }
  defstruct [:socket, buffer: ""]

  @impl :ranch_protocol
  def start_link(ref, _socket, transport, opts) do
    {:ok, :proc_lib.spawn_link(__MODULE__, :init, [{ref, transport, opts}])}
  end

  @impl GenServer
  def init({ref, transport, _opts}) do
    {:ok, socket} = :ranch.handshake(ref)
    :ok = transport.setopts(socket, active: true)
    state = %__MODULE__{socket: socket, buffer: ""}
    :gen_server.enter_loop(__MODULE__, [], state)
  end

  @impl GenServer
  def handle_info({:tcp, socket, data}, %{socket: socket, buffer: buffer} = state) do
    buffer = buffer <> data
    state = %{state | buffer: buffer}

    {queries, reply} = handle_buffer({[], state})
    :ok = Enum.each(queries, &Intersection.send_query/1)

    reply
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    {:stop, :normal, state}
  end

  @spec handle_buffer({[Tablespoon.Query.t()], t()}) :: {[Tablespoon.Query.t()], gen_server_reply}
        when gen_server_reply: {:noreply, t} | {:stop, :normal, t}
  def handle_buffer(acc)

  def handle_buffer({queries, %{buffer: ""} = state}) do
    {Enum.reverse(queries), {:noreply, state}}
  end

  def handle_buffer({queries, %{buffer: "GET " <> _} = state}) do
    _ = Logger.info("#{__MODULE__} got HTTP request, ignoring socket=#{inspect(state.socket)}")
    {Enum.reverse(queries), {:stop, :normal, state}}
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
    {Enum.reverse(queries), {:noreply, state}}
  end

  defp handle_decoded_buffer({:error, :ignore, _buffer}, queries, state) do
    {Enum.reverse(queries), {:stop, :normal, state}}
  end

  defp handle_decoded_buffer({:error, error, _buffer}, queries, state) do
    _ =
      Logger.error(fn ->
        "#{__MODULE__} error while parsing socket=#{inspect(state.socket)} error=#{inspect(error)} buffer=#{
          inspect(state.buffer, limit: 2048)
        }"
      end)

    {Enum.reverse(queries), {:stop, :normal, state}}
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
