defmodule TablespoonWeb.IntersectionsControllerTest do
  @moduledoc false
  use TablespoonWeb.ConnCase, async: true

  describe "index/2" do
    test "renders an HTML page", %{conn: conn} do
      conn = get(conn, "/")

      assert html_response(conn, 200) =~ "Intersections"
    end
  end
end
