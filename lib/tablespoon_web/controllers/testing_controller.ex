defmodule TablespoonWeb.TestingController do
  @moduledoc """
  Renders a view to help with testing.
  """
  use TablespoonWeb, :controller

  def index(conn, _params) do
    send_file(conn, 200, "priv/testing.html")
  end
end
