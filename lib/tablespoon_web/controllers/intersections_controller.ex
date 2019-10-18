defmodule TablespoonWeb.IntersectionsController do
  @moduledoc """
  Renders a table with the current intersection configuration.
  """
  use TablespoonWeb, :controller

  def index(conn, _params) do
    configs = Enum.sort_by(Tablespoon.Application.configs(), & &1.alias)
    render(conn, :index, title: "Intersections", configs: configs)
  end
end
