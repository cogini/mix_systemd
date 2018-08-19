defmodule MixSystemdTest do
  use ExUnit.Case
  doctest MixSystemd

  test "greets the world" do
    assert MixSystemd.hello() == :world
  end
end
