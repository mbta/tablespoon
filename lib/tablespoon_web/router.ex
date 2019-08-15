defmodule TablespoonWeb.Router do
  use TablespoonWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TablespoonWeb do
    pipe_through :api
  end
end
