defmodule Mix.Tasks.Systemd do
  @moduledoc false

  # Directory where `mix systemd.generate` stores output files,
  # e.g. _build/prod/systemd
  @output_dir "systemd"

  # Directory where `mix systemd.init` copies templates in user project
  @template_dir "rel/templates/systemd"

  @app :mix_systemd

  @doc "Generate cfg from mix.exs and app config"
  @spec parse_args(OptionParser.argv()) :: Keyword.t()
  def parse_args(argv) do
    opts = [strict: [version: :string]]
    {overrides, _} = OptionParser.parse!(argv, opts)

    user_config = Application.get_all_env(@app) |> Keyword.merge(overrides)
    mix_config = Mix.Project.config()

    create_config(mix_config, user_config)
  end

  @doc "Generate cfg based on params"
  @spec create_config(Keyword.t(), Keyword.t()) :: Keyword.t()
  def create_config(mix_config, user_config) do
    # Elixir app name, from mix.exs
    app_name = mix_config[:app]

    # External name, used for files and directories
    ext_name =
      app_name
      |> to_string
      |> String.replace("_", "-")

    # Name of systemd unit
    service_name = ext_name

    # Elixir camel case module name version of snake case app name
    module_name =
      app_name
      |> to_string
      |> String.split("_")
      |> Enum.map_join("", &String.capitalize/1)

    base_dir = user_config[:base_dir] || "/srv"
    build_path = Mix.Project.build_path()

    output_dir =
      user_config[:output_dir] || Path.join([build_path, @output_dir, "/lib/systemd/system"])

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
        # :runtime,       # App runtime files which may be deleted between runs, /run/#{ext_name}
        # :configuration, # Config files, Erlang cookie
        # :logs,          # External log file, not journald
        # :cache,         # App cache files which can be deleted
        # :state,         # App state persisted between runs
        # :tmp,           # App temp files
      ],

      # Standard directory locations for under systemd for various purposes.
      # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectory=
      #
      # Recent versions of systemd (since 235) will create directories if they
      # don't exist if they are configured in the unit file.
      #
      # For security, modes are tighter than the systemd default of 755.
      # Note that these are strings, not integers, as they are actually octal.
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
      # Whether to preserve the runtime dir on app restart
      # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectoryPreserve=
      # "no" | "yes" | "restart"
      runtime_directory_preserve: "no",
      state_directory: service_name,
      state_directory_base: "/var/lib",
      state_directory_mode: "750",
      tmp_directory: service_name,
      tmp_directory_base: "/var/tmp",
      tmp_directory_mode: "750",

      # Elixir 1.9+ mix releases or Distillery
      # :mix | :distillery
      release_system: :mix,

      # Service start type
      # https://www.freedesktop.org/software/systemd/man/systemd.service.html#Type=
      # :simple | :exec | :notify | :forking
      service_type: :simple,

      # How service is restarted on update
      # :systemctl | :systemd_flag | :touch
      restart_method: :systemctl,

      # Mix build_path
      build_path: build_path,

      # Staging output directory for generated files
      output_dir: output_dir,

      # Directory with templates which override defaults
      template_dir: @template_dir,
      mix_env: Mix.env(),

      # LANG variable
      env_lang: "en_US.utf8",

      # Number of open file descriptors, LimitNOFILE
      # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#LimitCPU=
      limit_nofile: 65_535,

      # File mode creation mask, UMask
      # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#UMask=
      umask: "0027",

      # Environment files to read, e.g.
      # env files to read, e.g.
      # The "-" at the beginning means that the file is optional
      env_files: [
        # ["-", :configuration_dir, "/environment"],
        # ["-", :deploy_dir, "/etc/environment"],
      ],

      # Misc env vars to set
      env_vars: [
        #  PORT=8080

        #  Use runtime dir for tmp files
        #  ["RELEASE_TMP=", :runtime_dir]

        #  Distillery
        #  Use runtime dir for tmp and startup log
        #  ["RELEASE_MUTABLE_DIR=", :runtime_dir]
        #  "REPLACE_OS_VARS=true",
      ],

      # Script run by envronment config systemd unit
      runtime_environment_service_script: nil,

      # ExecStartPre commands to run before ExecStart
      # https://www.freedesktop.org/software/systemd/man/systemd.service.html#ExecStartPre=
      exec_start_pre: [],

      # Whether the service shall be restarted when the service process exits, is killed, or times out
      # https://www.freedesktop.org/software/systemd/man/systemd.service.html#Restart=
      restart: "always",

      # Time to sleep before restarting a service
      # https://www.freedesktop.org/software/systemd/man/systemd.service.html#RestartSec=
      restart_sec: nil,

      # Time to wait for start-up
      # https://www.freedesktop.org/software/systemd/man/systemd.service.html#TimeoutStartSec=
      timeout_start_sec: nil,

      # Wrapper script for ExecStart
      exec_start_wrap: nil,

      # Start unit after other systemd unit targets
      unit_after_targets: [],

      # Start runtime environment script after other systemd unit targets
      runtime_environment_unit_after_targets: [],

      # Enable chroot
      chroot: false,
      read_write_paths: [],
      read_only_paths: [],
      inaccessible_paths: [],

      # Enable extra restrictions
      paranoia: false,

      # Config keys which have variable expansion
      expand_keys: [
        :env_files,
        :env_vars,
        :runtime_environment_service_script,
        :exec_start_pre,
        :exec_start_wrap,
        :read_write_paths,
        :read_only_paths,
        :inaccessible_paths
      ],

      # Add your keys here
      expand_keys_extra: []
    ]

    # Override values from user config
    cfg = Keyword.merge(defaults, user_config)

    # Calcualate values from other things
    cfg =
      Keyword.merge(
        [
          releases_dir: cfg[:releases_dir] || Path.join(cfg[:deploy_dir], "releases"),
          scripts_dir: cfg[:scripts_dir] || Path.join(cfg[:deploy_dir], "bin"),
          flags_dir: cfg[:flags_dir] || Path.join(cfg[:deploy_dir], "flags"),
          current_dir: cfg[:current_dir] || Path.join(cfg[:deploy_dir], "current"),
          runtime_dir:
            cfg[:runtime_dir] || Path.join(cfg[:runtime_directory_base], cfg[:runtime_directory]),
          configuration_dir:
            cfg[:configuration_dir] ||
              Path.join(cfg[:configuration_directory_base], cfg[:configuration_directory]),
          logs_dir: cfg[:logs_dir] || Path.join(cfg[:logs_directory_base], cfg[:logs_directory]),
          tmp_dir: cfg[:logs_dir] || Path.join(cfg[:tmp_directory_base], cfg[:tmp_directory]),
          state_dir:
            cfg[:state_dir] || Path.join(cfg[:state_directory_base], cfg[:state_directory]),
          cache_dir:
            cfg[:cache_dir] || Path.join(cfg[:cache_directory_base], cfg[:cache_directory]),

          # Loation of pid file when running as a daemon
          pid_file:
            cfg[:pid_file] ||
              Path.join([cfg[:runtime_directory_base], cfg[:runtime_directory], "#{app_name}.pid"]),

          # Chroot dir
          root_directory: cfg[:root_directory] || Path.join(cfg[:deploy_dir], "current"),
          start_command:
            cfg[:start_command] || start_command(cfg[:service_type], cfg[:release_system]),
          exec_start_wrap: ensure_trailing_space(cfg[:exec_start_wrap]),
          unit_after_targets:
            if cfg[:runtime_environment_service_script] do
              cfg[:unit_after_targets] ++ ["#{cfg[:service_name]}-runtime-environment.service"]
            else
              cfg[:unit_after_targets]
            end
        ],
        cfg
      )

    # Set things based on values computed above
    cfg =
      Keyword.merge(
        [
          working_dir: cfg[:working_dir] || cfg[:current_dir]
        ],
        cfg
      )

    # for {key, value} <- cfg do
    #   Mix.shell.info "cfg: #{key} #{inspect value}"
    # end

    expand_keys(cfg, cfg[:expand_keys] ++ cfg[:expand_keys_extra])
  end

  # Set start comand based on systemd service type and release system
  @doc false
  @spec start_command(atom, atom) :: binary
  def start_command(service_type, release_system)
  # https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-daemon-mode-unix-like
  def start_command(:forking, :mix), do: "daemon"
  def start_command(type, :mix) when type in [:simple, :exec, :notify], do: "start"
  # https://hexdocs.pm/distillery/tooling/cli.html#release-tasks
  def start_command(:forking, :distillery), do: "start"
  def start_command(type, :distillery) when type in [:simple, :exec, :notify], do: "foreground"

  # Make sure that script name has a trailing space if defined
  @doc false
  @spec ensure_trailing_space(nil | binary) :: binary
  def ensure_trailing_space(nil), do: ""

  def ensure_trailing_space(value) do
    if String.ends_with?(value, " "), do: value, else: value <> " "
  end

  # Expand cfg vars in keys
  @doc false
  @spec expand_keys(Keyword.t(), list(atom)) :: Keyword.t()
  def expand_keys(cfg, keys) do
    Enum.reduce(Keyword.take(cfg, keys), cfg, fn {key, value}, acc ->
      Keyword.put(acc, key, expand_value(value, acc))
    end)
  end

  # Expand vars in value or list of values
  @doc false
  @spec expand_value(atom | binary | list, Keyword.t()) :: binary | list(binary)
  def expand_value(values, cfg) when is_list(values) do
    Enum.map(values, &expand_vars(&1, cfg))
  end

  def expand_value(value, cfg), do: expand_vars(value, cfg)

  # Expand references in values
  @doc false
  @spec expand_vars(binary | nil | atom | list, Keyword.t()) :: binary
  def expand_vars(value, _cfg) when is_binary(value), do: value
  def expand_vars(nil, _cfg), do: ""

  def expand_vars(key, cfg) when is_atom(key) do
    case Keyword.fetch(cfg, key) do
      {:ok, value} ->
        expand_vars(value, cfg)

      :error ->
        to_string(key)
    end
  end

  def expand_vars(terms, cfg) when is_list(terms) do
    Enum.map_join(terms, "", &expand_vars(&1, cfg))
  end

  def expand_vars(value, _cfg), do: to_string(value)
end

defmodule Mix.Tasks.Systemd.Init do
  @moduledoc """
  Initialize template files.

  ## Command line options

    * `--template_dir` - target directory

  ## Usage

      # Copy default templates into your project
      mix systemd.init
  """
  @shortdoc "Initialize template files"
  use Mix.Task

  @app :mix_systemd

  @impl Mix.Task
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
  Create systemd unit files for project.

  ## Usage

      # Create unit files
      MIX_ENV=prod mix systemd.generate
  """
  @shortdoc "Create systemd unit file"
  use Mix.Task

  alias MixSystemd.Templates

  @impl Mix.Task
  def run(args) do
    cfg = Mix.Tasks.Systemd.parse_args(args)

    dest_dir = cfg[:output_dir]
    service_name = cfg[:service_name]

    write_template(cfg, dest_dir, "systemd.service", "#{service_name}.service")

    if cfg[:restart_method] == :systemd_flag do
      write_template(cfg, dest_dir, "restart.service", "#{service_name}-restart.service")
      write_template(cfg, dest_dir, "restart.path", "#{service_name}-restart.path")
    end

    if cfg[:runtime_environment_service] do
      write_template(
        cfg,
        dest_dir,
        "runtime-environment.service",
        "#{service_name}-runtime-environment.service"
      )
    end
  end

  defp write_template(cfg, dest_dir, template, file) do
    # target_file = Path.join(dest_dir, file)
    # Mix.shell.info "Generating #{target_file} from template #{template}"
    Templates.write_template(cfg, dest_dir, template, file)
  end
end
