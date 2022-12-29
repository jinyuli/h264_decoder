defmodule VodServerTest do
  use ExUnit.Case
  doctest VodServer

  test "greets the world" do
    assert VodServer.hello() == :world
  end
end
