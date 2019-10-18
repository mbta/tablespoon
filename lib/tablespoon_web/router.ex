defmodule TablespoonWeb.Router do
  use TablespoonWeb, :router

  get "/priority", TablespoonWeb.PriorityController, :index
  get "/_testing", TablespoonWeb.TestingController, :index
end
