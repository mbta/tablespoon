defmodule TablespoonWeb.ErrorsTest do
  @moduledoc false
  use TablespoonWeb.ConnCase, async: true

  describe "404" do
    @tag :capture_log
    test "renders an HTML page", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> get("/not-found")

      assert html_response(conn, 404) =~ "Not Found"
    end
  end
end
