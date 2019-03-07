# mix_systemd

This library generates a
[systemd](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
unit file to manage an Elixir application.

At its heart, it's a mix task which reads information about the project from
`mix.exs` plus optional library configuration in `config/config.exs` and
generates systemd unit files using Eex templates.

The goal is that the project defaults will generate a good systemd unit file,
and standard options support more specialized use cases. If you need more
customization, you can check the local copy of the templates into source
control and modify them (and patches are welcome).

It uses standard systemd functions and conventions to make your app
a more "native" OS citizen, and takes advantage of systemd features to improve
security and reliability.

While it can be used standalone, more advanced use cases require scripts
from e.g. [mix_deploy](https://github.com/cogini/mix_deploy).

## Installation

Add `mix_systemd` to the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mix_systemd, "~> 0.1.0"}
  ]
end
```

## Usage

This library works similarly to [Distillery](https://hexdocs.pm/distillery/home.html).
The `init` task copies template files into your project, then the `generate`
task uses them to create the output files.

Run this command to initialize templates under the `rel/templates/systemd` directory:

```shell
MIX_ENV=prod systemd.init
```

Next, generate output files under `_build/#{mix_env}/systemd/lib/systemd/system`.

```shell
MIX_ENV=prod mix systemd.generate
```

## Configuration

The library gets standard information in `mix.exs`, e.g. the app name and
version, then calculates default values for its configuration parameters.

You can override these parameters using settings in `config/config.exs`, e.g.:

```elixir
config :mix_systemd,
    app_user: "app",
    app_group: "app",
    base_dir: "/opt",
    env_vars: [
        "REPLACE_OS_VARS=true",
    ]
```

The following sections describe configuration options.
See `lib/mix/tasks/systemd.ex` for all the details.

If you need to make changes not supported by the config options, then you can
check the templates into source control from `rel/templates/systemd` and make
your own changes.

### Basics

`app_name`: Elixir application name, an atom, from the `app` field in the `mix.exs` project.

`version`: `version` from the `mix.exs` project.

`ext_name`: External name, used for files and directories.
Default is `app_name` with underscores converted to "-".

`service_name`: Name of the systemd service, default `ext_name`.

`base_dir`: Base directory where app files go, default `/srv` to
follow systemd conventions.

`deploy_dir`: Directory where app files go, default `#{base_dir}/#{ext_name}`

`app_user`: OS user account that the app runs under, default `ext_name`.

`app_group`: OS group account, default `ext_name`.

### Directories

Modern Linux defines a set of directories which apps use for common
purposes, e.g. configuration or cache files.
See https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectory=

This library defines these directories based on the app name, e.g. `/etc/#{ext_name}`.
It only creates directories that the app uses, default `runtime` (`/run/#{ext_name}`)
and `configuration` (`/etc/#{ext_name}`). If your app uses other dirs, set them in the
`dirs` var:

```elixir
dirs: [
  :runtime,       # App runtime files which may be deleted between runs, /run/#{ext_name}
                  # Needed for RELEASE_MUTABLE_DIR, runtime-environment or conform
  :configuration, # App configuration, e.g. db passwords, /etc/#{ext_name}
  # :state,       # App data or state persisted between runs, /var/lib/#{ext_name}
  # :cache,       # App cache files which can be deleted, /var/cache/#{ext_name}
  # :logs,        # App external log files, not via journald, /var/log/#{ext_name}
  # :tmp,         # App temp files, /var/tmp/#{ext_name}
],
```

For security, we set permissions to 750, more restrictive than the
systemd defaults of 755. You can configure them with e.g. `configuration_directory_mode`.
See the defaults in `lib/mix/tasks/systemd.ex`.

More recent versions of systemd (after 235) will create these directories at start
time based on the settings in the unit file. For earlier systemd versions, you need
to create them beforehand using scripts, e.g. [mix_deploy](https://github.com/cogini/mix_deploy).

`systemd_version`: Sets the systemd version on the target system, default 235.
This determines which systemd features the library will enable. If you are
targeting an older OS release, you may need to change it. Here are the systemd
versions in common OS releases:

* CentOS 7: 219
* Ubuntu 16.04: 229
* Ubuntu 18.04: 237

### Additional directories

The library assumes a directory structure under `deploy_dir` which allows it to handle multiple releases,
similar to [Capistrano](https://capistranorb.com/documentation/getting-started/structure/).

* `scripts_dir`:  deployment scripts which e.g. start and stop the unit, default `bin`.
* `current_dir`: where the current Erlang release is unpacked or referenced by symlink, default `current`.
* `releases_dir`: where versioned releases are unpacked, default `releases`.
* `flags_dir`: dir for flag files to trigger restart, e.g. when `restart_method` is `:systemd_flag`, default `flags`.

When using multiple releases and symlinks, the deployment process works like this:

1. Create a new directory for the release with a timestamp like
   `/srv/foo/releases/20181114T072116`.

2. Upload the new release tarball to the server and unpack it to the releases dir

3. Make a symlink from `/srv/#{ext_name}/current` to the new release dir.

4. Restart the app.

If you are only keeping a single version, then you would deploy it to
the `/srv/#{ext_name}/current` dir.

### Environment vars

The library sets a few common env vars directly in the unit file:

* `PORT`: `env_port` var, default 4000
* `LANG`: `env_lang` var, default `en_US.UTF-8`
* `MIX_ENV`: `mix_env` var, default `Mix.env()`
* `RELEASE_MUTABLE_DIR`: default `runtime_dir`, e.g. `/run/#{ext_name}`

* `DEFAULT_COOKIE_FILE`: `cookie_dir` var, value `:home`, `:runtime_dir`,
   `:configuration_dir`, or a string starting with "/".

   Default is `:home`, which does not set the var. The default behavior of the VM boot scripts
   will generate a cookie and write it to `$HOME/.erlang.cookie`.
   If you specify a value for `cookie_dir`, then the systemd unit will set
   `DEFAULT_COOKIE_FILE` to the corresponding directory and the startup scripts will
   use it. `cookie_file` sets the name of the file in the dir, default `erlang.cookie`.

   If you are only using the app on a single node, then the cookie is not important,
   though it should be strong for security. If you need to connect to the node remotely
   via a remote shell, you will need the cookie.

   If you are running in a cluster, then they need to share the key, and you should
   manage the cookie as a secret in your deployment process. In that case,
   you can write it to the specified directory, and the Erlang node will use it.

* `CONFORM_CONF_PATH`: Default `/etc/#{ext_name}/#{app_name}.conf`, set if `conform` var is `true`

You can set misc additional vars in the `env_vars` config var, e.g.:

```elixir
env_vars: [
    "REPLACE_OS_VARS=true",
]
```

The unit file also attempts to read environment vars from a series of files:

* `etc/environment` within the release, e.g. `/srv/app/currrent/etc/environment`
* `#{deploy_dir}/etc/environment`, e.g. `/srv/app/etc/environment`
* `#{configuration_dir}/environment`, e.g. `/etc/app/environment`
* `#{runtime_dir}/runtime-environment`, e.g. `/run/app/runtime-environment`

Later values override earlier values, so you can set defaults which get
overridden in the deployment or runtime environment.

### Systemd and OS

`limit_nofile`: Limit on open files, systemd
[LimitNOFILE](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#LimitCPU=),
default 65535.

`umask`: Process umask, systemd
[UMask](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#UMask=),
default 0027

`restart_sec`: Time to wait between restarts, systemd
[RestartSec](https://www.freedesktop.org/software/systemd/man/systemd.service.html#RestartSec=),
default 5 sec.

`service_type`: `:simple | :exec | :notify | :forking`. Default `:forking`.

In theory, "modern" applications are not supposed to fork. The Erlang VM runs
pretty well in "foreground" mode, but it is really expecting to run as a
standard Unix-style daemon. Systemd expects foregrounded apps to die when their
pipe closes, so this library runs forking mode by default. It sets `pid_file`
to `#{runtime_directory}/#{app_name}.pid` and sets the `PIDFILE` env var to tell
the boot scripts where it is. See
https://elixirforum.com/t/systemd-cant-shutdown-my-foreground-app-cleanly/14581/2

To run in foreground mode, set `service_type` to `:simple` or `:exec`. Note
that in `simple` mode, systemd doesn't actually check if the app started
successfully, it just keeps going. If something depends on your app being up,
`:exec` may be better.

`restart_method`: `:systemd_flag | :systemctl | :touch`. Default `:systemctl`

Set this to `:systemd_flag`, and the library will generate an additional
unit file which watches for changes to a flag file and restarts the
main unit. This allows updates to be pushed to the target machine by an
unprivileged user account which does not have permissions to restart
processes. `touch` the file `#{flags_dir}/restart.flag` and systemd will restart the unit.

### Runtime configuration

For configuration, we use a combination of build time settings, deploy
time settings, and runtime settings.

The configuration settings in `config/prod.exs` are baked into the release. We
can then extend them with machine-specific configuration stored in the
configuration dir `/etc/#{ext_name}` which are read by the app on startup.

In on-premises deployments, we might generate the machine-specific
configuration once when setting up the app.

In cloud and other dynamic environments, we may run from a read-only image,
e.g. an Amazon AMI, which gets configured at start up based on the environment
by copying the config from an S3 bucket. We can also read configuration
settings like database host and login from a configuration store like
[AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-paramstore.html)
or etcd.

Some things change dynamically each time the app starts, e.g. the IP address of
the machine, or periodically, such as AWS access keys in an IAM instance role.

[Conform](https://github.com/bitwalker/conform) is a popular way of making a
machine-specific config file. Set `conform` to `true`, and the library will
set `CONFORM_CONF_PATH` to `/etc/#{ext_name}/#{app_name}.conf`. Conform has been
depreciated in favor of [TOML](https://github.com/bitwalker/toml-elixir), so
you should use that instead.

This library supports three ways to get runtime config:

#### `ExecStartPre` scripts

These scripts run before the main `ExecStart` script runs.

You can specify multiple scripts in the `exec_start_pre` var. If the name
starts with a slash, it is run directly, otherwise it is expected to be in the
directory specified by `scripts_dir` (normally `#{deploy_dir}/bin`).

These scripts should generally write config to either the systemd
`configuration_dir` (`/etc`) for persistent config or `runtime_dir` (`/run`)
for data which systemd should clean up on restart.

#### Wrapper script

Instead of running the main `ExecStart` script directly, run a shell script which
sets up the environment, then `exec` the main script.

This is most useful for things that are truly dynamic and may change on restart.
For example, if the app is in a cluster, we might get the IP address of the
primary network interface to set the node name.

Set `runtime_environment_wrap` to `true` and set
`runtime_environment_wrap_script` to the name of the script. Default is the
`deploy-runtime-environment-wrap` script from `mix_deploy`.

Systemd starts units in parallel when possible, but we may need to enforce ordering.
Set `runtime_environment_service_after` to the names of systemd units that the
script depends on. For example, set it to `cloud-init.target` if you are using cloud-init to get
[runtime network information](https://cloudinit.readthedocs.io/en/latest/topics/network-config.html#network-configuration-outputs).

#### Systemd service

We can run our own service to collect runtime data and configure the system.
Set `runtime_environment_service` to `true` and this library will create
a service which runs the script specified by `runtime_environment_service_script`
and make it a runtime dependency of the main script. This ensures that the data
is available before the app starts.

## Security

`paranoia`: Enable systemd security options, default `false`.

    NoNewPrivileges=yes
    PrivateDevices=yes
    PrivateTmp=yes
    ProtectSystem=full
    ProtectHome=yes
    PrivateUsers=yes
    ProtectKernelModules=yes
    ProtectKernelTunables=yes
    ProtectControlGroups=yes
    MountAPIVFS=yes
                                                                                                    │
`chroot`: Enable systemd [chroot](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RootDirectory=), default `false`.
Sets systemd `RootDirectory` is set to `current_dir`. You can also set systemd [ReadWritePaths=, ReadOnlyPaths=,
InaccessiblePaths=](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#ReadWritePaths=)
with the `read_write_paths`, `read_only_paths` and `inaccessible_paths` vars, respectively.
