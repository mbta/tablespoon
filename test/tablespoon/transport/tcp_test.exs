defmodule Tablespoon.Transport.TCPTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Tablespoon.Transport.TCP

  @localhost "127.0.0.1"

  setup do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, {:active, true}])
    {:ok, listener_port} = :inet.port(listener)
    {:ok, listener: listener, listener_port: listener_port}
  end

  describe "send/1" do
    test "send a packet to the given host/port", %{
      listener: listener,
      listener_port: listener_port
    } do
      {:ok, tcp} = TCP.connect(TCP.new(host: @localhost, port: listener_port))
      {:ok, accept} = :gen_tcp.accept(listener)

      test_packet = inspect(:erlang.unique_integer())

      assert {:ok, ^tcp} = TCP.send(tcp, test_packet)
      assert_receive {:tcp, ^accept, ^test_packet}
    end

    test "returns an error if we can't connect to the port" do
      assert {:error, _} = TCP.connect(TCP.new(host: @localhost, port: 0))
    end
  end

  describe "stream/2" do
    test "receives a packet", %{listener: listener, listener_port: listener_port} do
      {:ok, tcp} = TCP.connect(TCP.new(host: @localhost, port: listener_port))
      {:ok, accept} = :gen_tcp.accept(listener)

      test_packet = inspect(:erlang.unique_integer())
      :ok = :gen_tcp.send(accept, test_packet)

      receive do
        x ->
          assert {:ok, ^tcp, [data: ^test_packet]} = TCP.stream(tcp, x)
      end
    end

    test "receives a closed message if the other side disconnects", %{
      listener: listener,
      listener_port: listener_port
    } do
      {:ok, tcp} = TCP.connect(TCP.new(host: @localhost, port: listener_port))
      {:ok, accept} = :gen_tcp.accept(listener)

      :ok = :gen_tcp.close(accept)

      receive do
        x ->
          assert {:ok, tcp, [:closed]} = TCP.stream(tcp, x)
          refute tcp.socket
      end
    end

    test "ignores unknown messages" do
      tcp = TCP.new(host: @localhost, port: 0)
      assert TCP.stream(tcp, :other_message) == :unknown
    end
  end
end
