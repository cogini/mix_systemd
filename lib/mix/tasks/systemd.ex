defmodule Mix.Tasks.Systemd do
  # Directory where `mix systemd.generate` stores output files,
  # e.g. _build/prod/systemd
  @output_dir "systemd"

  # Directory where `mix systemd.init` copies templates in user project
  @template_dir "rel/templates/systemd"

  @spec parse_args(OptionParser.argv()) :: Keyword.t
  def parse_args(argv) do
    {overrides, _} = OptionParser.parse!(argv, [])

    user_config = Application.get_all_env(:mix_systemd)
    mix_config = Mix.Project.config()

    # Elixir app name, from mix.exs
    app_name = mix_config[:app]

    # External name, used for files and directories
    ext_name = app_name
               |> to_string
               |> String.replace("_", "-")

    # Name of systemd unit
    service_name = ext_name

    # Elixir camel case module name version of snake case app name
    module_name = app_name
                  |> to_string
                  |> String.split("_")
                  |> Enum.map(&String.capitalize/1)
                  |> Enum.join("")

    base_dir = user_config[:base_dir] || "/srv"

    build_path = Mix.Project.build_path()

    defaults = [
      # Elixir application name
      app_name: app_name,

      # Elixir module name in camel case
      module_name: module_name,

      # Name of release
      release_name: app_name,

      # External name, used for files and directories
      ext_name: ext_name,

      # Name of service
      service_name: service_name,

      # OS user to run app
      app_user: ext_name,
      app_group: ext_name,

      # Name in logs
      syslog_identifier: service_name,

      # Base directory on target system, e.g. /srv
      base_dir: base_dir,

      # Directory for release files on target
      deploy_dir: "#{base_dir}/#{ext_name}",

      # Target systemd version
      # systemd_version: 219, # CentOS 7
      # systemd_version: 229, # Ubuntu 16.04
      # systemd_version: 237, # Ubuntu 18.04
      systemd_version: 235,

      dirs: [
        :runtime,         # RELEASE_TMP, RELEASE_MUTABLE_DIR, runtime environment
        :configuration,   # Config files, Erlang cookie
        # :logs,          # External log file, not journald
        # :cache,         # App cache files which can be deleted
        # :state,         # App state persisted between runs
        # :tmp,           # App temp files
      ],

      # Standard directory locations for under systemd for various purposes.
      # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectory=
      #
      # Recent versions of systemd will create directories if they don't exist
      # if they are specified in the unit file.
      #
      # For security, we default to modes which are tighter than the systemd
      # default of 755.
      # Note that these are strings, not integers.
      cache_directory: service_name,
      cache_directory_base: "/var/cache",
      cache_directory_mode: "750",
      configuration_directory: service_name,
      configuration_directory_base: "/etc",
      configuration_directory_mode: "750",
      logs_directory: service_name,
      logs_directory_base: "/var/log",
      logs_directory_mode: "750",
      runtime_directory: service_name,
      runtime_directory_base: "/run",
      runtime_directory_mode: "750",
      runtime_directory_preserve: "no",
      state_directory: service_name,
      state_directory_base: "/var/lib",
      state_directory_mode: "750",
      tmp_directory: service_name,
      tmp_directory_base: "/var/tmp",
      tmp_directory_mode: "750",

      # Mix releases in Elixir 1.9+ or Distillery
      release_system: :mix, # :mix | :distillery

      # Service start type
      service_type: :simple, # :simple | :exec | :notify | :forking

      # How service is restarted on update
      restart_method: :systemctl, # :systemctl | :systemd_flag | :touch

      # Mix build_path
      build_path: build_path,

      # Staging output directory for generated files
      output_dir: Path.join(build_path, @output_dir),

      # Directory with templates which override defaults
      template_dir: @template_dir,

      mix_env: Mix.env(),

      # LANG environment var for running scripts
      env_lang: "en_US.UTF-8",

      # Number of open file descriptors, LimitNOFILE
      # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#LimitCPU=
      limit_nofile: 65535,

      # File mode creation mask, UMask
      # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#UMask=
      umask: "0027",

      # Misc env vars to set, e.g.
      # env_vars: [
      #  "REPLACE_OS_VARS=true",
      #  {"RELEASE_MUTABLE_DIR", :runtime_dir}
      # ]
      env_vars: [],

      runtime_environment_service_script: nil,

      # ExecStartPre commands to run before ExecStart
      exec_start_pre: [],

      # time to sleep before restarting a service, RestartSec
      # https://www.freedesktop.org/software/systemd/man/systemd.service.html#RestartSec=
      restart_sec: 1,

      # Wrapper script for ExecStart
      exec_start_wrap: nil,

      # Start unit after other systemd unit targets
      unit_after_targets: [],

      # Enable chroot
      chroot: false,
      read_write_paths: [],
      read_only_paths: [],
      inaccessible_paths: [],

      # Enable extra restrictions
      paranoia: false,
    ]

    # Override values from user config
    cfg = defaults
          |> Keyword.merge(user_config)
          |> Keyword.merge(overrides)

    # Mix.shell.info "cfg: #{inspect cfg}"

    # Calcualate values from other things
    cfg = Keyword.merge([
      releases_dir: cfg[:releases_dir] || Path.join(cfg[:deploy_dir], "releases"),
      scripts_dir: cfg[:scripts_dir] || Path.join(cfg[:deploy_dir], "bin"),
      flags_dir: cfg[:flags_dir] || Path.join(cfg[:deploy_dir], "flags"),
      current_dir: cfg[:current_dir] || Path.join(cfg[:deploy_dir], "current"),

      start_command: cfg[:start_command] || start_command(cfg[:service_type], cfg[:release_system]),
      exec_start_wrap: exec_start_wrap(cfg[:exec_start_wrap]),
      unit_after_targets: if cfg[:runtime_environment_service_script] do
        cfg[:unit_after_targets] ++ ["#{cfg[:service_name]}-runtime-environment.service"]
      else
        cfg[:unit_after_targets]
      end,

      runtime_dir: cfg[:runtime_dir] || Path.join(cfg[:runtime_directory_base], cfg[:runtime_directory]),
      configuration_dir: cfg[:configuration_dir] || Path.join(cfg[:configuration_directory_base], cfg[:configuration_directory]),
      logs_dir: cfg[:logs_dir] || Path.join(cfg[:logs_directory_base], cfg[:logs_directory]),
      tmp_dir: cfg[:logs_dir] || Path.join(cfg[:tmp_directory_base], cfg[:tmp_directory]),
      state_dir: cfg[:state_dir] || Path.join(cfg[:state_directory_base], cfg[:state_directory]),
      cache_dir: cfg[:cache_dir] || Path.join(cfg[:cache_directory_base], cfg[:cache_directory]),

      pid_file: cfg[:pid_file] || Path.join([cfg[:runtime_directory_base], cfg[:runtime_directory], "#{app_name}.pid"]),

      # Chroot config
      root_directory: cfg[:root_directory] || Path.join(cfg[:deploy_dir], "current"),
    ], cfg)

    # Set things based on values computed above
    cfg = Keyword.merge([
      working_dir: cfg[:working_dir] || cfg[:current_dir],
    ], cfg)

    # Expand values in env vars
    expand_env_vars(cfg)
  end

  @doc "Set start comand based on systemd service type and release system"
  @spec start_command(atom, atom) :: binary
  def start_command(service_type, release_system)
  # https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-daemon-mode-unix-like
  def start_command(:forking, :mix), do: "daemon"
  def start_command(type, :mix) when type in [:simple, :exec, :notify], do: "start"
  # https://hexdocs.pm/distillery/tooling/cli.html#release-tasks
  def start_command(:forking, :distillery), do: "start"
  def start_command(type, :distillery) when type in [:simple, :exec, :notify], do: "foreground"

  @doc "Make sure that script name has a space afterwards"
  @spec exec_start_wrap(nil | binary) :: binary
  def exec_start_wrap(nil), do: ""
  def exec_start_wrap(script) do
    if String.ends_with?(script, " "), do: script, else: script <> " "
  end

  @doc "Expand symbolic vars in env vars"
  @spec expand_env_vars(Keyword.t) :: Keyword.t
  def expand_env_vars(cfg) do
    env_vars =
      Enum.reduce(cfg[:env_vars], [],
      fn(value, acc) when is_binary(value) ->
          [value | acc]
        ({name, value}, acc) when is_atom(value) ->
          ["#{name}=#{cfg[value]}" | acc]
        ({name, value}, acc) ->
          ["#{name}=#{value}" | acc]
      end)
    Keyword.put(cfg, :env_vars, env_vars)
  end

  @doc "Expand references in values"
  def expand_vars(cfg, keys) do
    Enum.reduce(keys, cfg,
      fn(key, acc) ->
        value = acc[key]
        if is_atom(value) and cfg[value] do
          Keyword.put(acc, key, value)
        else
          acc
        end
      end)
  end

end

defmodule Mix.Tasks.Systemd.Init do
  @moduledoc """
  Initialize systemd template files.

  ## Command line options

    * `--template_dir` - target directory

  ## Usage

      # Copy default templates into your project
      mix systemd.init
  """
  @shortdoc "Initialize systemd template files"
  use Mix.Task

  @app :mix_systemd

  @spec run(OptionParser.argv()) :: no_return
  def run(args) do
    cfg = Mix.Tasks.Systemd.parse_args(args)

    template_dir = cfg[:template_dir]
    app_dir = Application.app_dir(@app, ["priv", "templates"])

    :ok = File.mkdir_p(template_dir)
    {:ok, _files} = File.cp_r(app_dir, template_dir)
  end

end

defmodule Mix.Tasks.Systemd.Generate do
  @moduledoc """
  Create systemd unit files for Elixir project.

  ## Usage

      # Create unit files for prod
      MIX_ENV=prod mix systemd.generate
  """
  @shortdoc "Create systemd unit file"
  use Mix.Task

  alias MixSystemd.Templates

  @spec run(OptionParser.argv()) :: no_return
  def run(args) do
    # Parse options
    # opts = parse_args(args)
    # verbosity = Keyword.get(opts, :verbosity)
    # Shell.configure(verbosity)

    cfg = Mix.Tasks.Systemd.parse_args(args)

    dest_dir = Path.join([cfg[:output_dir], "/lib/systemd/system"])
    service_name = cfg[:service_name]

    write_template(cfg, dest_dir, "systemd.service", "#{service_name}.service")

    if cfg[:restart_method] == :systemd_flag do
      write_template(cfg, dest_dir, "restart.service", "#{service_name}-restart.service")
      write_template(cfg, dest_dir, "restart.path", "#{service_name}-restart.path")
    end

    if cfg[:runtime_environment_service_script] do
      write_template(cfg, dest_dir, "runtime-environment.service", "#{service_name}-runtime-environment.service")
    end

  end

  defp write_template(cfg, dest_dir, template, file) do
    target_file = Path.join(dest_dir, file)
    Mix.shell.info "Generating #{target_file} from template #{template}"
    Templates.write_template(cfg, dest_dir, template, file)
  end
end
