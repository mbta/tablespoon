defmodule TablespoonWeb.IntersectionsView do
  use TablespoonWeb, :view

  def ms_to_minute(milliseconds) do
    div(milliseconds, 60_000)
  end

  def friendly_time({h, m, _s}) do
    h = Integer.to_string(h)

    m =
      m
      |> Integer.to_string()
      |> String.pad_leading(2, "0")

    [h, ?:, m]
  end
end
