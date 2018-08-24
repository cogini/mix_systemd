defmodule Mix.Tasks.Systemd.Unit do
  @moduledoc """
  Create systemd unit files for Elixir project.

  ## Command line options

    * `--version` - selects a specific app version

  ## Usage

      # Creates revision from current release with MIX_ENV=dev (the default)
      mix systemd.unit

      # Builds a release with MIX_ENV=prod
      MIX_ENV=prod mix systemd.unit
  """
  @shortdoc "Create systemd unit file"
  use Mix.Task

  @app :mix_systemd
  @template_dir "systemd"

  @spec run(OptionParser.argv()) :: no_return
  def run(_args) do
    # Parse options
    # opts = parse_args(args)
    # verbosity = Keyword.get(opts, :verbosity)
    # Shell.configure(verbosity)

    config = config()

    build_path = Mix.Project.build_path()
    dest_dir = Path.join(build_path, "systemd/lib/systemd/system")
    write_template(config, dest_dir, "systemd.service", "#{config[:service_name]}.service")

    if config[:restart_flag] do
      write_template(config, dest_dir, "restart.service", "#{config[:service_name]}-restart.service")
      write_template(config, dest_dir, "restart.path", "#{config[:service_name]}-restart.path")
    end

  end

  @doc false
  @spec parse_args(OptionParser.argv()) :: Keyword.t() | no_return
  def parse_args(argv) do
    switches = [
      silent: :boolean,
      quiet: :boolean,
      verbose: :boolean,
      version: :string,
    ]
    {args, _argv} = OptionParser.parse!(argv, strict: switches)

    defaults = %{
      verbosity: :normal,
    }

    args = Enum.reduce args, defaults, fn arg, config ->
      case arg do
        {:verbose, _} ->
          %{config | :verbosity => :verbose}
        {:quiet, _} ->
          %{config | :verbosity => :quiet}
        {:silent, _} ->
          %{config | :verbosity => :silent}
        {key, value} ->
          Map.put(config, key, value)
      end
    end

    Map.to_list(args)
  end

  @spec config() :: Keyword.t
  def config, do: config(Mix.Project.config())

  @spec config(Keyword.t) :: Keyword.t
  def config(project_config) do
    config = project_config[:mix_systemd] || []

    app_name = to_string(project_config[:app])
    service_name = config[:service_name] || String.replace(app_name, "_", "-")
    app_user = config[:app_user] || service_name
    deploy_user = config[:deploy_user] || service_name

    env_port = config[:env_port] || 4000

    base_path = config[:base_path] || "/srv/#{service_name}"
    release_path = "#{base_path}/current"

    defaults = [
      # Options
      # Enable conform config file
      conform: false,
      # Enable chroot
      chroot: false,
      # Enable extra restrictions
      paranoia: false,

      # Enable restart from flag file
      restart_flag: false,
      restart_path: "#{base_path}/restart.flag",

      app: project_config[:app],
      # systemd service name corresponding to app name
      # This is used to name the service files and directories
      service_name: service_name,
      # Output directory base
      build_path: Mix.Project.build_path(),
      # Target systemd version
      systemd_version: 235,

      # Base directory on target system
      base_path: base_path,
      # Directory where release will be extracted on target
      release_path: release_path,
      conform_conf_path: "/etc/#{service_name}/conform.conf",
      # Directory writable by app user, used for temp files, e.g. conform
      release_mutable_dir: "/run/#{service_name}",

      # OS user accounts
      app_user: app_user,
      app_group: app_user,
      deploy_user: deploy_user,
      deploy_group: deploy_user,

      mix_env: Mix.env(),
      env_lang: "en_US.UTF-8",
      env_port: env_port,
      limit_nofile: 65535,
      umask: "0027",
      restart_sec: 5,

      runtime_directory: service_name,
      runtime_directory_mode: "750",
      runtime_directory_preserve: "no",
      configuration_directory: service_name,
      configuration_directory_mode: "750",
      logs_directory: service_name,
      logs_directory_mode: "750",
      state_directory: service_name,
      state_directory_mode: "750",

      # Chroot config
      root_directory: release_path,
      read_write_paths: [],
      read_only_paths: [],
      inaccessible_paths: [],
    ]

    Keyword.merge(defaults, config)
  end

  @spec write_template(Keyword.t, Path.t, String.t) :: :ok
  def write_template(config, target_path, template) do
    :ok = File.mkdir_p(target_path)
    {:ok, data} = template_name(template, config)
    :ok = File.write(Path.join(target_path, template), data)
  end

  @spec write_template(Keyword.t, Path.t, String.t, Path.t) :: :ok
  def write_template(config, target_path, template, filename) do
    :ok = File.mkdir_p(target_path)
    {:ok, data} = template_name(template, config)
    :ok = File.write(Path.join(target_path, filename), data)
  end

  @spec template_name(Path.t, Keyword.t) :: {:ok, String.t} | {:error, term}
  def template_name(name, params \\ []) do
    template_name = "#{name}.eex"
    template_path = params[:template_path] || @template_dir
    override_path = Path.join([template_path, template_name])
    if File.exists?(override_path) do
      template_path(override_path)
    else
      Application.app_dir(@app, Path.join("priv", "templates"))
      |> Path.join(template_name)
      |> template_path(params)
    end
  end

  @doc "Eval template with params"
  @spec template_path(String.t, Keyword.t) :: {:ok, String.t} | {:error, term}
  def template_path(template_path, params \\ []) do
    {:ok, EEx.eval_file(template_path, params, [trim: true])}
  rescue
    e ->
      {:error, {:template, e}}
  end

end
