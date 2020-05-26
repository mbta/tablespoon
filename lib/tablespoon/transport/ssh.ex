defmodule Tablespoon.Transport.SSH do
  @moduledoc """
  Transport for sending/receiving bytes over SSH.

  To use:

  ssh = SSH.new(host: host, username: username, password: password)
  {:ok. ssh} = SSH.connect(ssh)
  {:ok, ssh} = SSH.send(ssh, "echo hello\n")
  receive do
    x ->
      {:ok, ssh, results} = SSH.stream(ssh, x)
  end

  The results returned from stream/2 can be:

  - {:data, binary}
  - :closed
  """
  @behaviour Tablespoon.Transport
  @connect_timeout 5_000
  @negotiation_timeout @connect_timeout * 2
  @keep_alive_timeout 240_000

  require Logger

  @derive {Inspect, except: [:password]}
  defstruct [:host, :username, :password, :conn_ref, :channel_id, :keep_alive_ref, port: 22]

  @impl Tablespoon.Transport
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = ssh) do
    with {:ok, conn_ref} <-
           :ssh.connect(
             to_charlist(ssh.host),
             ssh.port,
             [
               user: to_charlist(ssh.username),
               password: to_charlist(ssh.password),
               silently_accept_hosts: true,
               user_interaction: false,
               save_accepted_host: false,
               quiet_mode: false,
               connect_timeout: @connect_timeout,
               keepalive: true
             ],
             @negotiation_timeout
           ),
         {:ok, channel_id} <- :ssh_connection.session_channel(conn_ref, @connect_timeout),
         :success <- :ssh_connection.ptty_alloc(conn_ref, channel_id, []),
         :ok <- :ssh_connection.shell(conn_ref, channel_id) do
      ssh = %{ssh | conn_ref: conn_ref, channel_id: channel_id}
      ssh = schedule_keep_alive(ssh)
      {:ok, ssh}
    else
      {:error, l} when is_list(l) ->
        # convert charlist errors into binary errors, since that's what we
        # use elsewhere in Elixir
        {:error, IO.iodata_to_binary(l)}

      :failure ->
        # from ptty_alloc or shell
        {:error, "Unable to allocate PTY or create shell"}

      e ->
        e
    end
  end

  @impl Tablespoon.Transport
  def stream(
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = ssh,
        {:ssh_cm, conn_ref, {:data, channel_id, 0, data}}
      ) do
    ssh = schedule_keep_alive(ssh)
    {:ok, ssh, [{:data, data}]}
  end

  def stream(
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = ssh,
        {:ssh_cm, conn_ref, {:exit_status, channel_id, _status}}
      ) do
    # exit status message: we don't do anything with this
    {:ok, ssh, []}
  end

  def stream(
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = ssh,
        {:ssh_cm, conn_ref, {:eof, channel_id}}
      ) do
    # the other side closed their write connection: nothing to do
    {:ok, ssh, []}
  end

  def stream(
        %__MODULE__{conn_ref: conn_ref, channel_id: channel_id} = ssh,
        {:ssh_cm, conn_ref, {:closed, channel_id}}
      ) do
    do_close(ssh)
  end

  def stream(%__MODULE__{conn_ref: conn_ref} = ssh, {:ssh_cm, conn_ref, message}) do
    # This is a message meant for us, but that we don't know how to process
    _ =
      Logger.warn(fn ->
        "#{__MODULE__} unexpected message ssh=#{inspect(ssh)} message=#{inspect(message)}"
      end)

    {:ok, ssh, []}
  end

  def stream(
        %__MODULE__{conn_ref: conn_ref} = ssh,
        {:ssh_keep_alive, conn_ref}
      ) do
    # NB: this request/reply happens syncronously!
    case :ssh_connection_handler.global_request(
           conn_ref,
           'keep-alive@mbta.com',
           true,
           [],
           @connect_timeout
         ) do
      {reply, _} when reply in [:success, :failure] ->
        ssh = schedule_keep_alive(ssh)
        {:ok, ssh, []}

      {:error, e} ->
        _ =
          Logger.warn(fn ->
            "unexpected reply from keep-alive ssh=#{inspect(ssh)} error=#{inspect(e)}"
          end)

        ssh = do_close(ssh)
        {:ok, ssh, [{:error, e}]}
    end
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{} = ssh, data) when is_binary(data) or is_list(data) do
    with :ok <- :ssh_connection.send(ssh.conn_ref, ssh.channel_id, data) do
      {:ok, ssh}
    end
  end

  def do_close(ssh) do
    _ = :ssh.close(ssh.conn_ref)
    ssh = cancel_keep_alive(%{ssh | conn_ref: nil, channel_id: nil})
    {:ok, ssh, [:closed]}
  end

  defp schedule_keep_alive(ssh) do
    ssh = cancel_keep_alive(ssh)
    ref = Process.send_after(self(), {:ssh_keep_alive, ssh.conn_ref}, @keep_alive_timeout)
    %{ssh | keep_alive_ref: ref}
  end

  defp cancel_keep_alive(ssh) do
    _ =
      if is_reference(ssh.keep_alive_ref) do
        Process.cancel_timer(ssh.keep_alive_ref)
      end

    %{ssh | keep_alive_ref: nil}
  end
end
