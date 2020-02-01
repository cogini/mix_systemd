defmodule MixSystemdTest do
  use ExUnit.Case, async: true

  test "create_config/2" do
    mix_config = Mix.Project.config()
    user_config = [base_dir: "/opt"]
    cfg = Mix.Tasks.Systemd.create_config(mix_config, user_config)

    assert cfg[:app_name] == :mix_systemd
    assert cfg[:ext_name] == "mix-systemd"
    assert cfg[:module_name] == "MixSystemd"
    assert cfg[:deploy_dir] == "/opt/mix-systemd"
    assert cfg[:releases_dir] == "/opt/mix-systemd/releases"
    assert cfg[:configuration_dir] == "/etc/mix-systemd"
    assert cfg[:pid_file] == "/run/mix-systemd/mix_systemd.pid"
    assert cfg[:working_dir] == "/opt/mix-systemd/current"
    assert cfg[:start_command] == "start"
  end

  describe "ensure_trailing_space/1" do
    test "nil returns empty string" do
      assert Mix.Tasks.Systemd.ensure_trailing_space(nil) == ""
    end

    test "value ending with space returned as is" do
      assert Mix.Tasks.Systemd.ensure_trailing_space("foo ") == "foo "
    end

    test "value without space has space added" do
      assert Mix.Tasks.Systemd.ensure_trailing_space("foo") == "foo "
    end
  end

  describe "expand_vars/2" do
    test "nil returns empty string" do
      assert Mix.Tasks.Systemd.expand_vars(nil, []) == ""
    end

    test "string returns itself" do
      assert Mix.Tasks.Systemd.expand_vars("", []) == ""
      assert Mix.Tasks.Systemd.expand_vars("foo", []) == "foo"
    end

    test "atom returns value from cfg" do
      assert Mix.Tasks.Systemd.expand_vars(:foo, foo: "bar") == "bar"
    end

    test "atom returns value recursively" do
      assert Mix.Tasks.Systemd.expand_vars(:foo, foo: :bar, bar: "baz") == "baz"
    end

    test "unknown atom returns string value of atom" do
      assert Mix.Tasks.Systemd.expand_vars(:foo, []) == "foo"
    end

    test "integers are converted to string" do
      assert Mix.Tasks.Systemd.expand_vars(42, []) == "42"
    end

    test "list of terms returns string value" do
      assert Mix.Tasks.Systemd.expand_vars(["one", "two", "three"], []) == "onetwothree"
    end

    test "list of terms expands vars" do
      assert Mix.Tasks.Systemd.expand_vars(
               [:deploy_dir, "/etc"],
               deploy_dir: "/srv/foo"
             ) == "/srv/foo/etc"

      assert Mix.Tasks.Systemd.expand_vars(
               ["!", :deploy_dir, "/bin/sync"],
               deploy_dir: "/srv/foo"
             ) == "!/srv/foo/bin/sync"
    end

    test "handles env vars" do
      assert Mix.Tasks.Systemd.expand_vars(
               ["RELEASE_MUTABLE_DIR=", :runtime_dir],
               runtime_dir: "/run/foo"
             ) == "RELEASE_MUTABLE_DIR=/run/foo"
    end
  end
end
