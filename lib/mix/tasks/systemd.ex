defmodule Mix.Tasks.Systemd.Unit do
  @moduledoc """
  Create systemd unit files for Elixir project.

  ## Command line options

    * `--version` - selects a specific app version

  ## Usage

      # Create systemd unit files with MIX_ENV=dev (the default)
      mix systemd.unit

      # Create unit files with MIX_ENV=prod
      MIX_ENV=prod mix systemd.unit
  """
  @shortdoc "Create systemd unit file"
  use Mix.Task

  alias MixSystemd.Templates

  # Name of app, used to get info from application environment
  @app :mix_systemd

  # Name of directory under build directory where module stores generated files
  @output_dir "mix_systemd"

  # Name of directory where user can override templates
  @template_override_dir "mix_systemd"

  @spec run(OptionParser.argv()) :: no_return
  def run(args) do
    # Parse options
    # opts = parse_args(args)
    # verbosity = Keyword.get(opts, :verbosity)
    # Shell.configure(verbosity)

    cfg = parse_args(args)

    dest_dir = Path.join([cfg[:build_path], @output_dir, "/lib/systemd/system"])
    service_name = cfg[:service_name]

    write_template(cfg, dest_dir, "systemd.service", "#{service_name}.service")

    if cfg[:restart_flag] do
      write_template(cfg, dest_dir, "restart.service", "#{service_name}-restart.service")
      write_template(cfg, dest_dir, "restart.path", "#{service_name}-restart.path")
    end
  end

  defp write_template(cfg, dest_dir, template, file) do
    target_file = Path.join(dest_dir, file)
    Mix.shell.info "Generating #{target_file} from template #{template}"
    Templates.write_template(cfg, dest_dir, template, file)
  end

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
      # Enable conform config file
      conform: false,

      # Enable chroot
      chroot: false,

      # Enable extra restrictions
      paranoia: false,

      # Enable restart from flag file
      restart_flag: false,

      restart_method: :systemd_flag, # :systemd_flag | :systemctl | :touch

      # OS user to own files and run app
      app_user: ext_name,
      app_group: ext_name,

      # Target systemd version
      # systemd_version: 219, # CentOS 7
      # systemd_version: 229, # Ubuntu 16.04
      systemd_version: 235,

      # PORT environment var
      env_port: 4000,

      #####

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
      # LANG environment var for running scripts
      env_lang: "en_US.UTF-8",
      limit_nofile: 65535,
      umask: "0027",
      restart_sec: 5,

      # Elixir application name
      app_name: app_name,

      # Name of files and directories
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
      template_dir: Path.join("templates", @template_override_dir),
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
      scripts_dir: Path.join(cfg[:deploy_dir], "scripts"),
      flags_dir: Path.join(cfg[:deploy_dir], "flags"),
      current_dir: Path.join(cfg[:deploy_dir], "current"),

      runtime_dir: Path.join(cfg[:runtime_directory_base], cfg[:runtime_directory]),
      conf_dir: Path.join(cfg[:configuration_directory_base], cfg[:configuration_directory]),
      logs_dir: Path.join(cfg[:logs_directory_base], cfg[:logs_directory]),
      tmp_dir: Path.join(cfg[:tmp_directory_base], cfg[:tmp_directory]),
      state_dir: Path.join(cfg[:state_directory_base], cfg[:state_directory]),
      cache_dir: Path.join(cfg[:cache_directory_base], cfg[:cache_directory]),

      conform_conf_path: Path.join([cfg[:configuration_directory_base], cfg[:configuration_directory], "#{app_name}.conf"]),

      # Chroot config
      root_directory: Path.join(cfg[:deploy_dir], "current"),
      read_write_paths: [],
      read_only_paths: [],
      inaccessible_paths: [],

    ], cfg)
  end

  # @spec config() :: Keyword.t
  # def config, do: config(Mix.Project.config())

  # @spec config(Keyword.t) :: Keyword.t
  # def config(project_config) do
  #   config = project_config[:mix_systemd] || []

  #   app_name = to_string(project_config[:app])
  #   service_name = config[:service_name] || String.replace(app_name, "_", "-")
  #   app_user = config[:app_user] || service_name
  #   deploy_user = config[:deploy_user] || service_name

  #   env_port = config[:env_port] || 4000

  #   base_path = config[:base_path] || "/srv/#{service_name}"
  #   release_path = "#{base_path}/current"

  #   defaults = [
  #     # Options
  #     # Enable conform config file
  #     conform: false,
  #     # Enable chroot
  #     chroot: false,
  #     # Enable extra restrictions
  #     paranoia: false,

  #     # Enable restart from flag file
  #     restart_flag: false,
  #     restart_path: "#{base_path}/restart.flag",

  #     app: project_config[:app],
  #     # systemd service name corresponding to app name
  #     # This is used to name the service files and directories
  #     service_name: service_name,
  #     # Output directory base
  #     build_path: Mix.Project.build_path(),
  #     # Target systemd version
  #     systemd_version: 235,

  #     # Base directory on target system
  #     base_path: base_path,
  #     # Directory where release will be extracted on target
  #     release_path: release_path,
  #     conform_conf_path: "/etc/#{service_name}/#{app_name}.conf",
  #     # Directory writable by app user, used for temp files, e.g. conform
  #     release_mutable_dir: "/run/#{service_name}",

  #     # OS user accounts
  #     app_user: app_user,
  #     app_group: app_user,
  #     deploy_user: deploy_user,
  #     deploy_group: deploy_user,

  #     mix_env: Mix.env(),
  #     env_lang: "en_US.UTF-8",
  #     env_port: env_port,
  #     limit_nofile: 65535,
  #     umask: "0027",
  #     restart_sec: 5,

  #     runtime_directory: service_name,
  #     runtime_directory_mode: "750",
  #     runtime_directory_preserve: "no",
  #     configuration_directory: service_name,
  #     configuration_directory_mode: "750",
  #     logs_directory: service_name,
  #     logs_directory_mode: "750",
  #     state_directory: service_name,
  #     state_directory_mode: "750",

  #     # Chroot config
  #     root_directory: release_path,
  #     read_write_paths: [],
  #     read_only_paths: [],
  #     inaccessible_paths: [],
  #   ]

  #   Keyword.merge(defaults, config)
  # end

  # @doc false
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
