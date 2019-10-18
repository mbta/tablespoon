defmodule TablespoonWeb.Router do
  use TablespoonWeb, :router

  pipeline :browser do
    plug :accepts, ~w(html)
  end

  scope "/" do
    pipe_through([:browser])

    get "/", TablespoonWeb.IntersectionsController, :index
    get "/priority", TablespoonWeb.PriorityController, :index
    get "/_testing", TablespoonWeb.TestingController, :index
  end
end
