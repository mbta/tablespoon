defmodule Tablespoon.Transport.SSHTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Tablespoon.Transport.SSH

  # from https://www.sftp.net/public-online-sftp-servers
  @test_host "test.rebex.net"
  @test_username "demo"
  @test_password "password"
  @timeout 2000

  describe "connect/1" do
    test "returns an error if the connection fails" do
      ssh = SSH.new(username: "", password: "", host: "localhost")
      assert {:error, _} = SSH.connect(ssh)
    end

    @tag :rebex
    test "returns {:ok, term} for a good connection" do
      ssh = new_test()
      assert {:ok, %SSH{}} = SSH.connect(ssh)
    end
  end

  describe "stream/2" do
    @tag :rebex
    test "processes messages" do
      {:ok, ssh} = SSH.connect(new_test())
      {:ok, ssh} = SSH.send(ssh, "exit\r\n")
      {:ok, messages} = test_stream(ssh)
      assert [{:data, <<_::binary>>} | _] = messages
      assert List.last(messages) == :closed
    end

    test "ignores messages meant for other people" do
      assert SSH.stream(new_test(), :other_message) == :unknown
    end

    @tag :rebex
    test "re-connecting ignores messages from the old connection" do
      {:ok, ssh} = SSH.connect(new_test())
      {:ok, ssh} = SSH.connect(ssh)
      {:ok, ssh} = SSH.send(ssh, "exit\r\n")
      {:ok, messages} = test_stream(ssh)
      unknown_messages = for {:unknown, _} = message <- messages, do: message
      assert unknown_messages == []
    end
  end

  defp new_test do
    SSH.new(host: @test_host, username: @test_username, password: @test_password)
  end

  defp test_stream(ssh, messages \\ []) do
    receive do
      x ->
        {:ok, ssh, new_messages} =
          case SSH.stream(ssh, x) do
            :unknown ->
              [{:unknown, x}]

            other ->
              other
          end

        messages = messages ++ new_messages

        if :closed in new_messages do
          {:ok, messages}
        else
          test_stream(ssh, messages ++ new_messages)
        end
    after
      @timeout ->
        {:timeout, messages}
    end
  end
end
