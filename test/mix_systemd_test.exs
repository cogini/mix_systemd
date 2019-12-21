defmodule MixSystemdTest do
  use ExUnit.Case, async: true

  describe "exec_start_wrap" do
    test "nil returns empty string" do
      assert Mix.Tasks.Systemd.exec_start_wrap(nil) == ""
    end
    test "value ending with space returned as is" do
      assert Mix.Tasks.Systemd.exec_start_wrap("foo ") == "foo "
    end
    test "value without space has space added" do
      assert Mix.Tasks.Systemd.exec_start_wrap("foo") == "foo "
    end
  end
end
