defmodule TablespoonWeb.TestingController do
  @moduledoc """
  Renders a view to help with testing.
  """
  use TablespoonWeb, :controller

  def index(conn, _params) do
    testing_path = Application.app_dir(:tablespoon, "priv/testing.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, testing_path)
  end
end
