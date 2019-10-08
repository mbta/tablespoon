defmodule Tablespoon.Transport.PMPPMultiplexTest do
  @moduledoc false
  use ExUnit.Case

  alias Tablespoon.Transport.PMPPMultiplex

  @id_mfa {__MODULE__, :id, []}

  describe "send + stream" do
    test "receives an echo message" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 2, id_mfa: @id_mfa)
      {:ok, t} = PMPPMultiplex.connect(t)
      message = test_message()
      {:ok, t} = PMPPMultiplex.send(t, message)

      receive do
        x ->
          assert_from_one_of(x, [{t, message}])
      end
    end

    test "two different transports receive different messages" do
      transport = Echo.new()
      t = PMPPMultiplex.new(transport: transport, address: 3, id_mfa: @id_mfa)
      t2 = PMPPMultiplex.new(transport: transport, address: 3, id_mfa: @id_mfa)
      {:ok, t} = PMPPMultiplex.connect(t)
      {:ok, t2} = PMPPMultiplex.connect(t2)

      # different refs, same PID
      refute t.from == t2.from
      assert elem(t.from, 0) == elem(t2.from, 0)

      message = test_message()
      message2 = test_message()
      {:ok, t} = PMPPMultiplex.send(t, :binary.bin_to_list(message))
      {:ok, t2} = PMPPMultiplex.send(t2, message2)

      pairs = [{t, message}, {t2, message2}]

      seen =
        receive do
          x ->
            assert_from_one_of(x, pairs)
        end

      receive do
        x ->
          assert_from_one_of(x, pairs -- [seen])
      end
    end

    test "closing the child returns a closed message" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 4, id_mfa: @id_mfa)
      {:ok, t} = PMPPMultiplex.connect(t)
      # breaking into the struct to get the child we're connected to
      {pid, _} = t.from
      GenServer.stop(pid)

      receive do
        x ->
          assert {:ok, %PMPPMultiplex{}, [:closed]} = PMPPMultiplex.stream(t, x)
      end
    end

    @tag :capture_log
    test "receiving a message with an unexpected id stops the child" do
      t =
        PMPPMultiplex.new(transport: Echo.new(), address: 5, id_mfa: {__MODULE__, :unique_id, []})

      {:ok, t} = PMPPMultiplex.connect(t)
      message = test_message()
      {:ok, t} = PMPPMultiplex.send(t, message)

      receive do
        x ->
          assert {:ok, %PMPPMultiplex{}, [:closed]} = PMPPMultiplex.stream(t, x)
      end
    end

    test "closing the child fails to send" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 6, id_mfa: @id_mfa)
      {:ok, t} = PMPPMultiplex.connect(t)
      # breaking into the struct to get the child we're connected to
      {pid, _} = t.from
      GenServer.stop(pid)

      assert {:error, :not_started} = PMPPMultiplex.send(t, "")
    end

    test "closing the upstream transport closes the multiplex transport" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 7, id_mfa: @id_mfa)
      {:ok, t} = PMPPMultiplex.connect(t)
      {:ok, t} = PMPPMultiplex.send(t, "-1")

      receive do
        x ->
          assert {:ok, %PMPPMultiplex{}, [:closed]} = PMPPMultiplex.stream(t, x)
      end
    end

    test "sending errors are returned to the client" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 8, id_mfa: @id_mfa)
      {:ok, t} = PMPPMultiplex.connect(t)
      assert {:error, :not_sent} = PMPPMultiplex.send(t, "-2")
    end

    test "max_in_flight limits the number of requests that can be active" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 9, id_mfa: @id_mfa, max_in_flight: 1)
      {:ok, t} = PMPPMultiplex.connect(t)
      assert {:ok, t} = PMPPMultiplex.send(t, "-3")
      assert {:error, :too_many_in_flight} = PMPPMultiplex.send(t, "1")
    end

    test "handles multiple responses in the same packet" do
      t = PMPPMultiplex.new(transport: Echo.new(), address: 10, id_mfa: @id_mfa)
      {:ok, t} = PMPPMultiplex.connect(t)
      assert {:ok, t} = PMPPMultiplex.send(t, "-3")
      assert {:ok, t} = PMPPMultiplex.send(t, "-4")
      ref = make_ref()

      Kernel.send(self(), ref)

      receive do
        ^ref ->
          assert false, "timeout"

        x ->
          assert {:ok, %PMPPMultiplex{}, [{:data, "-3"}]} = PMPPMultiplex.stream(t, x)
      end

      receive do
        ^ref ->
          assert false, "timeout"

        x ->
          assert {:ok, %PMPPMultiplex{}, [{:data, "-4"}]} = PMPPMultiplex.stream(t, x)
      end
    end

    defp assert_from_one_of(x, pairs) do
      pairs =
        for {t, message} = pair <- pairs do
          case PMPPMultiplex.stream(t, x) do
            :unknown ->
              nil

            response ->
              assert {:ok, %PMPPMultiplex{}, [{:data, ^message}]} = response
              pair
          end
        end

      assert [seen] = Enum.filter(pairs, &is_tuple/1)
      seen
    end
  end

  defp test_message do
    Integer.to_string(:erlang.unique_integer([:positive]))
  end

  def id(binary) when is_binary(binary) do
    {:ok, String.to_integer(binary)}
  end

  def unique_id(_) do
    {:ok, :erlang.unique_integer()}
  end
end

defmodule Echo do
  @moduledoc "Echo transport"
  @behaviour Tablespoon.Transport

  defstruct [:ref, :saved]

  @impl Tablespoon.Transport
  def new(_opts \\ []) do
    %__MODULE__{}
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = t) do
    {:ok, %{t | ref: make_ref()}}
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{ref: ref} = t, iodata) when is_reference(ref) do
    binary = IO.iodata_to_binary(iodata)

    cond do
      binary =~ "-1" ->
        Kernel.send(self(), {ref, :closed})
        {:ok, t}

      binary =~ "-2" ->
        {:error, :not_sent}

      binary =~ "-3" ->
        t = %{t | saved: binary}
        {:ok, t}

      binary =~ "-4" ->
        response = t.saved <> binary
        t = %{t | saved: nil}
        Kernel.send(self(), {ref, {:data, response}})
        {:ok, t}

      true ->
        wait_time = Enum.random(1..10)
        Process.send_after(self(), {ref, {:data, binary}}, wait_time)
        {:ok, t}
    end
  end

  def send(%__MODULE__{}, _) do
    {:error, :not_connected}
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{ref: ref} = t, {ref, message}) do
    {:ok, t, [message]}
  end
end
