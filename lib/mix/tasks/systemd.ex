defmodule Mix.Tasks.Systemd do
  # Name of app, used to get info from application environment
  @app :mix_systemd

  # Name of directory under build directory where module stores generated files
  @output_dir "systemd"

  # User template directory
  @template_dir "rel/templates/systemd"

  @spec parse_args(OptionParser.argv()) :: Keyword.t
  def parse_args(argv) do
    opts = [
      strict: [
        version: :string,
      ]
    ]
    {overrides, _} = OptionParser.parse!(argv, opts)

    mix_config = Mix.Project.config()
    user_config = Application.get_all_env(@app)

    app_name = mix_config[:app]
    ext_name = app_name
               |> to_string
               |> String.replace("_", "-")
    service_name = ext_name

    base_dir = user_config[:base_dir] || "/srv"

    build_path = Mix.Project.build_path()

    defaults = [
      service_type: :forking, # :simple | :exec | :notify | :forking

      # Enable conform config file
      conform: false,

      # Enable chroot
      chroot: false,

      # Enable extra restrictions
      paranoia: false,

      # Enable restart from flag file
      restart_flag: false,

      restart_method: :systemd_flag, # :systemd_flag | :systemctl | :touch

      # Create runtime-environment file for app
      runtime_environment_service: false,
      # Wrap app in runtime-environment script
      runtime_environment_wrap: false,
      runtime_environment_service_after: "cloud-init.target",

      # OS user to own files and run app
      app_user: ext_name,
      app_group: ext_name,

      # Target systemd version
      # systemd_version: 219, # CentOS 7
      # systemd_version: 229, # Ubuntu 16.04
      # systemd_version: 237, # Ubuntu 18.04
      systemd_version: 235,

      # PORT environment var
      env_port: 4000,

      # LANG environment var for running scripts
      env_lang: "en_US.UTF-8",

      # Misc env vars
      # env_vars: [
      #  "REPLACE_OS_VARS=true",
      # ]
      env_vars: [],

      # ExecStartPre commands to run before ExecStart
      exec_start_pre: [],

      # Limit on open files
      limit_nofile: 65535,
      umask: "0027",
      restart_sec: 5,

      dirs: [
        :runtime,         # needed for RELEASE_MUTABLE_DIR, runtime-environment or conform
        # :configuration, # needed for conform or other external app config file
        # :logs,          # needed for external log file, not journald
        # :cache,         # app cache files which can be deleted
        # :state,         # app state persisted between runs
        # :tmp,           # app temp files
      ],

      #####

      # These are the standard directory locations under systemd for various purposes.
      # More recent versions of systemd will create directories if they don't exist.
      # We default to modes which are tighter than the systemd default of 755.
      # https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectory=
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

      mix_env: Mix.env(),

      # Elixir application name, an atom
      app_name: app_name,

      # External name, used for files and directories
      ext_name: ext_name,

      # Name of service
      service_name: ext_name,

      # App version
      version: mix_config[:version],

      # Base directory on target system
      base_dir: base_dir,

      # Directory for release files on target
      deploy_dir: "#{base_dir}/#{ext_name}",

      # Mix build_path
      build_path: build_path,

      # Staging output directory for generated files
      output_dir: Path.join(build_path, @output_dir),

      # Directory with templates which override defaults
      template_dir: @template_dir,
    ]

    cfg = defaults
          |> Keyword.merge(user_config)
          |> Keyword.merge(overrides)

    # Default OS user and group names
    cfg = Keyword.merge([
      deploy_user: cfg[:app_user],
      deploy_group: cfg[:app_group],
    ], cfg)

    # Mix.shell.info "cfg: #{inspect cfg}"

    # Data calculated from other things
    Keyword.merge([
      releases_dir: Path.join(cfg[:deploy_dir], "releases"),
      scripts_dir: Path.join(cfg[:deploy_dir], "bin"),
      flags_dir: Path.join(cfg[:deploy_dir], "flags"),
      current_dir: Path.join(cfg[:deploy_dir], "current"),

      runtime_dir: Path.join(cfg[:runtime_directory_base], cfg[:runtime_directory]),
      configuration_dir: Path.join(cfg[:configuration_directory_base], cfg[:configuration_directory]),
      logs_dir: Path.join(cfg[:logs_directory_base], cfg[:logs_directory]),
      tmp_dir: Path.join(cfg[:tmp_directory_base], cfg[:tmp_directory]),
      state_dir: Path.join(cfg[:state_directory_base], cfg[:state_directory]),
      cache_dir: Path.join(cfg[:cache_directory_base], cfg[:cache_directory]),

      conform_conf_path: Path.join([cfg[:configuration_directory_base], cfg[:configuration_directory], "#{app_name}.conf"]),
      pid_file: Path.join([cfg[:runtime_directory_base], cfg[:runtime_directory], "#{app_name}.pid"]),

      # Chroot config
      root_directory: Path.join(cfg[:deploy_dir], "current"),
      read_write_paths: [],
      read_only_paths: [],
      inaccessible_paths: [],

    ], cfg)
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

  ## Command line options

    * `--version` - selects a specific app version

  ## Usage

      # Create systemd unit files with MIX_ENV=dev (the default)
      mix systemd.generate

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

    if cfg[:restart_flag] do
      write_template(cfg, dest_dir, "restart.service", "#{service_name}-restart.service")
      write_template(cfg, dest_dir, "restart.path", "#{service_name}-restart.path")
    end

    if cfg[:runtime_environment_service] do
      write_template(cfg, dest_dir, "runtime-environment.service", "#{service_name}-runtime-environment.service")
    end
  end

  defp write_template(cfg, dest_dir, template, file) do
    target_file = Path.join(dest_dir, file)
    Mix.shell.info "Generating #{target_file} from template #{template}"
    Templates.write_template(cfg, dest_dir, template, file)
  end

  # @spec parse_args(OptionParser.argv()) :: Keyword.t() | no_return
  # def parse_args(argv) do
  #   switches = [
  #     silent: :boolean,
  #     quiet: :boolean,
  #     verbose: :boolean,
  #     version: :string,
  #   ]
  #   {args, _argv} = OptionParser.parse!(argv, strict: switches)
  #
  #   defaults = %{
  #     verbosity: :normal,
  #   }
  #
  #   args = Enum.reduce args, defaults, fn arg, config ->
  #     case arg do
  #       {:verbose, _} ->
  #         %{config | :verbosity => :verbose}
  #       {:quiet, _} ->
  #         %{config | :verbosity => :quiet}
  #       {:silent, _} ->
  #         %{config | :verbosity => :silent}
  #       {key, value} ->
  #         Map.put(config, key, value)
  #     end
  #   end
  #
  #   Map.to_list(args)
  # end

end
