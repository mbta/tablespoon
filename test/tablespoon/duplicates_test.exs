defmodule Tablespoon.DuplicatesTest do
  use ExUnit.Case, async: true

  doctest Tablespoon.Duplicates

  alias Tablespoon.Duplicates

  describe "expire/2" do
    test "expire can happen in a different process from the owner" do
      dups = Duplicates.new()
      refute Duplicates.seen?(dups, 1, 0)
      {:ok, _pid} = Agent.start_link(fn -> Duplicates.expire(dups, 1) end)
      refute Duplicates.seen?(dups, 1, 2)
    end
  end
end
