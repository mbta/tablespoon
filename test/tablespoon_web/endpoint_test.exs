defmodule TablespoonWeb.EndpointTest do
  @moduledoc false
  use ExUnit.Case

  @finch __MODULE__.Finch

  describe "startup" do
    setup do
      start_supervised!({Finch, name: @finch})
      # start_supervised(TablespoonWeb.Endpoint) |> IO.inspect()
      :ok
    end

    test "returns an HTTP response" do
      # will crash if the request is unsuccessful
      response =
        :head
        |> Finch.build("http://127.0.0.1:4002/")
        |> Finch.request!(@finch)

      assert response.status == 200
    end
  end
end
