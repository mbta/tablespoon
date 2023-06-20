defmodule TablespoonWeb.ErrorView do
  use TablespoonWeb, :view

  # If you want to customize a particular status code
  # for a certain format, you may uncomment below.
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  @spec template_not_found(binary, map) :: map
  def template_not_found(template, _assigns) do
    status_message = Phoenix.Controller.status_message_from_template(template)

    case template do
      <<_status::binary-3, ".json">> -> %{errors: %{detail: status_message}}
      _ -> status_message
    end
  end
end
