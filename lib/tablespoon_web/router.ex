defmodule TablespoonWeb.Router do
  use TablespoonWeb, :router

  get "/priority", TablespoonWeb.Controllers.Priority, :index
end
