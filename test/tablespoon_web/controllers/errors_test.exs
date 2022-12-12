defmodule TablespoonWeb.ErrorsTest do
  @moduledoc false
  use TablespoonWeb.ConnCase, async: true

  describe "404" do
    @tag :capture_log
    test "renders an HTML page", %{conn: conn} do
      response =
        assert_error_sent 404, fn ->
          conn
          |> put_req_header("accept", "text/html")
          |> get("/not-found")
        end

      {code, _headers, body} = response

      assert code == 404
      assert body =~ "Not Found"
    end
  end
end
