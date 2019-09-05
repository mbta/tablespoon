defmodule TablespoonWeb.Router do
  use TablespoonWeb, :router

  get "/priority", TablespoonWeb.Controllers.Priority, :index
  get "/_testing", TablespoonWeb.Controllers.Testing, :index
end
