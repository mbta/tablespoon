defmodule TablespoonWeb.TestingControllerTest do
  @moduledoc false
  use TablespoonWeb.ConnCase, async: true

  describe "index/2" do
    test "renders an HTML page", %{conn: conn} do
      conn = get(conn, Routes.testing_path(conn, :index))

      assert html_response(conn, 200) =~ "Testing"
    end
  end
end
