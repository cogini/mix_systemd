![test workflow](https://github.com/cogini/mix_systemd/actions/workflows/test.yml/badge.svg)
[![Module Version](https://img.shields.io/hexpm/v/mix_systemd.svg)](https://hex.pm/packages/mix_systemd)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/mix_systemd/)
[![Total Download](https://img.shields.io/hexpm/dt/mix_systemd.svg)](https://hex.pm/packages/mix_systemd)
[![License](https://img.shields.io/hexpm/l/mix_systemd.svg)](https://github.com/cogini/mix_systemd/blob/master/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/cogini/mix_systemd.svg)](https://github.com/cogini/mix_systemd/commits/master)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)

# mix_systemd

This library generates a
[systemd](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
unit file to manage an Elixir release. It supports releases generated by Elixir 1.9+
[mix release](https://hexdocs.pm/mix/Mix.Tasks.Release.html) or
[Distillery](https://hexdocs.pm/distillery/home.html).

At its heart, it's a mix task which reads information about the project from
`mix.exs` and `config/config.exs` then generates systemd unit files using Eex
templates. The goal is that the project defaults will generate a good systemd
unit file, and standard options support more specialized use cases.

It uses standard systemd functions and conventions to make your app a more
"native" OS citizen and takes advantage of systemd features to improve
security and reliability. While it can be used standalone, more advanced use
cases use scripts from e.g., [mix_deploy](https://github.com/cogini/mix_deploy).

This [complete example app](https://github.com/cogini/mix-deploy-example) puts the
pieces together.

## Installation

Add `mix_systemd` to the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mix_systemd, "~> 0.7"},
  ]
end
```

## Configuration

The library tries to choose reasonable defaults, so you may not need to
configure anything. It reads the app name from `mix.exs` and calculates default
values for its configuration parameters. For example, if your app is named
`foo_bar`, it will create a service named `foo-bar`, deployed to
`/srv/foo-bar`, running under the user `foo-bar`.

You can override these parameters using settings in `config/config.exs`, e.g.:

```elixir
config :mix_systemd,
  app_user: "app",
  app_group: "app",
  base_dir: "/opt",
  env_vars: [
    "PORT=8080",
  ]
```

## Configuration strategies

There are four different kinds of things that we may want to configure:

1. Static information about application layout, e.g., file paths.
   This is the same for all machines in an environment, e.g., staging or prod.

2. Information specific to the environment, e.g., the hostname of the db
   server.

3. Secrets such as db passwords, API keys, or encryption keys.

4. Dynamic information such as the IP address of the server or other
   machines in the cluster.

Elixir has a couple of mechanisms for storing configuration. When you compile
the release, it converts Elixir-format config files like `config/config.exs`
into an initial application environment that is read by `Application.get_env/3`.
That's good for simple, relatively static apps. It's not ideal to store
passwords in the release file, though.

Elixir 1.9+ releases support dynamic configuration at runtime. You can configure
via the Elixir file `config/runtime.exs` which is loaded when the VM boots or
use the shell script `rel/env.sh.eex` to set environment vars.

With these you can theoretically do anything. In practice, however, it can be
more convenient and secure to process the config outside of the app. That's
where `mix_systemd` and `mix_deploy` come in.

## Environment vars

The simplest thing is to set environment variables. Add individual vars to
`env_vars`, and they will be set in the systemd unit file. Add files to
`env_files` and systemd will load them before starting your app.
Your application then calls `System.get_env/1` in `config/runtime.exs` or
application startup. Note that these environment vars are read at *runtime*,
not when building your app.

```elixir
env_vars: [
  # Set a variable, good for things that are not sensitive and don't change
  "PORT=8080",
],
dirs: [
  # create /etc/foo
  :configuration,
],
env_files: [
  # Read environment vars from the file /etc/foo/environment
  ["-", :configuration_dir, "/environment"],
]
```

`/etc/foo/environment` looks like:

    DATABASE_URL="ecto://foo_prod:Sekrit!@db.foo.local/foo_prod"
    SECRET_KEY_BASE="EOdJB1T39E5Cdeebyc8naNrOO4HBoyfdzkDy2I8Cxiq4mLvIQ/0tK12AK1ahrV4y"
    HOST="www.example.com"
    ASSETS_HOST="assets.example.com"
    RELEASE_COOKIE="LmCMGNz04yEJ4MQc6jt3cS7QjAppYOw_bQa7NE5hPZJGqL3Yry1jUg=="

`config/runtime.exs` does something like the following (the default files are good):

```elixir
config :foo, Foo.Repo,
  url: System.get_env("DATABASE_URL")

config :foo, FooWeb.Endpoint,
  http: [:inet6, port: System.get_env("PORT") || 4000],
  url: [host: System.get_env("HOST"), port: 443],
  static_url: [host: System.get_env("ASSETS_HOST"), port: 443],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  cache_static_manifest: "priv/static/cache_manifest.json"
```

### Copying files

The question is how to get the environment files onto the server. For simple
server deployments, we can copy the config to the server when doing the initial
setup.

In cloud environments, we may run from a read-only image, e.g., an Amazon AMI,
which gets configured at start up based on the environment by copying the
config from an S3 bucket, e.g.:

```shell
umask 077
aws s3 sync --exact-timestamps --no-progress "s3://${CONFIG_BUCKET}/" "/etc/foo/"
chown -R $DEPLOY_USER:$APP_GROUP /etc/foo
find /etc/foo -type f -exec chmod 640 {} \;
find /etc/foo -type d -exec chmod 750 {} \;
```

The following example runs the script `/srv/foo/bin/deploy-sync-config-s3` from
`mix_deploy`.  It uses an environment file in `/srv/foo/etc/environment`
to bootstrap the sync, e.g., setting the S3 bucket name. That file
is placed there by CodeDeploy at deploy time.

```elixir
config :mix_systemd,
  exec_start_pre: [
    # Run before starting the app
    # The `!` means the script is run as root, not as the app user
    ["!", :deploy_dir, "/bin/deploy-sync-config-s3"]
  ],
  dirs: [
    :configuration, # /etc/foo, app configuration, e.g. db passwords
    :runtime,       # /run/foo, temp files which may be deleted between runs
  ],
  env_files: [
    ["-", :deploy_dir, "/etc/environment"], # /srv/foo/etc/environment
  ]
  env_vars: [
    # Tell release to use /run/foo for temp files
    ["RELEASE_TMP=", :runtime_dir],
  ]
```

### Config providers

At a certain point, making everything into an environment var becomes annoying.
It's verbose and vars are simple strings, so you have to encode values
safely and convert them back to lists, integers or atoms.

[Config providers](https://hexdocs.pm/elixir/Config.Provider.html) let you load
files in standard formats like [TOML](https://hexdocs.pm/toml_config/readme.html).

```toml
[foo."Foo.Repo"]
url = "ecto://foo_prod:Sekrit!@db.foo.local/foo_prod"
pool_size = 15

[foo."FooWeb.Endpoint"]
secret_key_base = "EOdJB1T39E5Cdeebyc8naNrOO4HBoyfdzkDy2I8Cxiq4mLvIQ/0tK12AK1ahrV4y"
```

The app reads these config files on startup and merges them into the app
config.

```elixir
defp releases do
   [
     prod: [
       include_executables_for: [:unix],
       config_providers: [
         {TomlConfigProvider, path: "/etc/foo/config.toml"}
       ],
       steps: [:assemble, :tar]
     ]
   ]
 end
```

The startup scripts read the initial application environment compiled into the
release, parse the config file, merge the values, write it to a temp file, then
start the VM. Because of that, they need a writable directory. That is
configured using the `RELEASE_TMP` environment var, normally set to the app's
`runtime_dir`.

```elixir
dirs: [
  :configuration,
  :runtime,
],
env_vars: [
  ["RELEASE_TMP=", :runtime_dir],
],
```

### Config servers and vaults

You can also store config params in an external configuration system and
read them at runtime. An example is [AWS Systems Manager Parameter
Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-paramstore.html).

Set a parameter using the AWS CLI:

```shell
aws ssm put-parameter --name '/foo/prod/db/password' --type ‘SecureString’ --value 'Sekrit!"
```

While it's possible to read params in `config/runtime.exs`, it's tedious.
Better is to grab all of them at once and write them to a file, then read it in
with a Config Provider like [aws_ssm_provider](https://github.com/caredox/aws_ssm_provider).

```shell
aws --region us-east-1 ssm get-parameters-by-path --path "/foo/prod/" --recursive --with-decryption --query "Parameters[]" > /etc/foo/ssm.json
```

```elixir
defp releases do
   [
     prod: [
       include_executables_for: [:unix],
       config_providers: [
         {AwsSsmProvider, path: "/etc/foo/ssm.json"}
       ],
       steps: [:assemble, :tar]
     ]
   ]
 end
```

### Dynamic config

You can write code to do things like query the system for the primary IP
address, but `cloud-init`
[already does it](https://cloudinit.readthedocs.io/en/latest/topics/instancedata.html).
You just have to read the JSON file.

The most common use for this is setting up the VM node name. In `env.sh`:

```shell
CLOUD_NAME=$(jq -r '.v1.cloud_name' < /run/cloud-init/instance-data.json)
if [ "$CLOUD_NAME" = "digitalocean" ]; then
    IP_ADDR=$(jq -r '.ds.meta_data.interfaces.public[0].anchor_ipv4.ip_address' < /run/cloud-init/instance-data.json)
    DEFAULT_IPV4="$IP_ADDR"
elif [ "$CLOUD_NAME" = "aws" ]; then
    IP_ADDR=$(jq -r '.ds.meta_data."local-ipv4"' < /run/cloud-init/instance-data.json)
    # IP_ADDR=$(jq -r '.ds.meta_data."public-ipv4"' < /run/cloud-init/instance-data.json)
    AWS_REGION=$(jq -r '.v1.region' < /run/cloud-init/instance-data.json)
fi
RELEASE_DISTRIBUTION="name"
RELEASE_NODE="${RELEASE_NAME}@${IP_ADDR}"
```

### Security

An important security principle is
"[least privilege](https://www.cogini.com/blog/improving-app-security-with-the-principle-of-least-privilege/)".
If an attacker manages to compromise the app, then they can do whatever it has
permissions to do, not just what you expect. Because of that, I prefer that the
account that the app runs under cannot write files, and having a writable
config file that is also executed is the worst case scenario.

## Usage

First, use the `systemd.init` task to template files from the library to the
`rel/templates/systemd` directory in your project.

```shell
mix systemd.init
```

Next, generate output files in the build directory under
`_build/#{mix_env}/systemd/lib/systemd/system`.

```shell
MIX_ENV=prod mix systemd.generate
```

## Configuration options

The following sections describe common configuration options.
See `lib/mix/tasks/systemd.ex` for the details of more obscure options.

If you need to make changes not supported by the config options,
then you can check the templates in `rel/templates/systemd`
into source control and make your own changes.  Contributions are welcome!

### Basics

`app_name`: Elixir application name, an atom, from the `app` or `app_name`
field in the `mix.exs` project. For umbrella apps, set `app_name`.

`module_name`: Elixir camel case module name version of `app_name`, e.g.,
`FooBar`.

`release_name`: Name of release, default `app_name`.

`ext_name`: External name, used for files and directories, default `app_name`
with underscores converted to "-", e.g., `foo-bar`.

`service_name`: Name of the systemd service, default `ext_name`.

`release_system`: `:mix | :distillery`, default `:mix`

Identifies the system used to generate the releases,
[Mix](https://hexdocs.pm/mix/Mix.Tasks.Release.html) or
[Distillery](https://hexdocs.pm/distillery/home.html).

### Users

`app_user`: OS user account that the app runs under, default `ext_name`.

`app_group`: OS group account, default `ext_name`.

### Directories

`base_dir`: Base directory for app files on target, default `/srv`.

`deploy_dir`: Directory for app files on target, default `#{base_dir}/#{ext_name}`.

We use the
[standard app directories](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectory=),
for modern Linux systems. App files are under `/srv`, configuration under
`/etc`, transient files under `/run`, data under `/var/lib`.

Directories are named based on the app name, e.g. `/etc/#{ext_name}`.
The `dirs` variable specifies which directories the app uses.
By default, it doesn't set up anything. To enable them, configure the `dirs`
param, e.g.:

```elixir
dirs: [
  # :runtime,       # App runtime files which may be deleted between runs, /run/#{ext_name}
  # :configuration, # App configuration, e.g. db passwords, /etc/#{ext_name}
  # :state,         # App data or state persisted between runs, /var/lib/#{ext_name}
  # :cache,         # App cache files which can be deleted, /var/cache/#{ext_name}
  # :logs,          # App external log files, not via journald, /var/log/#{ext_name}
  # :tmp,           # App temp files, /var/tmp/#{ext_name}
],
```

Recent versions of systemd (since 235) will create these directories at
start time based on the settings in the unit file. With earlier systemd
versions, create them beforehand using installation scripts, e.g.,
[mix_deploy](https://github.com/cogini/mix_deploy).

For security, we set permissions to 750, more restrictive than the systemd
defaults of 755. You can configure them with variables like
`configuration_directory_mode`. See the defaults in
`lib/mix/tasks/systemd.ex`.

`systemd_version`: Sets the systemd version on the target system, default 235.
This determines which systemd features the library will enable. If you are
targeting an older OS release, you may need to change it. Here are the systemd
versions in common OS releases:

* CentOS 7: 219
* Ubuntu 16.04: 229
* Ubuntu 18.04: 237

### Additional directories

The library uses a directory structure under `deploy_dir` which supports
multiple releases, similar to [Capistrano](https://capistranorb.com/documentation/getting-started/structure/).

* `scripts_dir`: deployment scripts which, e.g., start and stop the unit, default `bin`.
* `current_dir`: where the current Erlang release is unpacked or referenced by symlink, default `current`.
* `releases_dir`: where versioned releases are unpacked, default `releases`.
* `flags_dir`: dir for flag files to trigger restart, e.g., when `restart_method` is `:systemd_flag`, default `flags`.

When using multiple releases and symlinks, the deployment process works as follows:

1. Create a new directory for the release with a timestamp like
   `/srv/foo/releases/20181114T072116`.

2. Upload the new release tarball to the server and unpack it to the releases dir.

3. Make a symlink from `/srv/#{ext_name}/current` to the new release dir.

4. Restart the app.

If you are only keeping a single version, then deploy it to the directory
`/srv/#{ext_name}/current`.

## Variable expansion

The following variables support variable expansion:

```elixir
expand_keys: [
  :env_files,
  :env_vars,
  :runtime_environment_service_script,
  :exec_start_pre,
  :exec_start_wrap,
  :read_write_paths,
  :read_only_paths,
  :inaccessible_paths,
]
```

You can specify values as a list of terms, and it will look up atoms as keys in
the config. This lets you reference, e.g., the deploy dir or configuration dir without
having to specify the full path, e.g., `["!", :deploy_dir, "/bin/myscript"]` gets
converted to `"!/srv/foo/bin/myscript"`.

### Environment vars

The library sets env vars in the unit file:

* `MIX_ENV`: `mix_env`, default `Mix.env()`
* `LANG`: `env_lang`, default `en_US.utf8`

* `RUNTIME_DIR`: `runtime_dir`, if `:runtime` in `dirs`
* `CONFIGURATION_DIR`: `configuration_dir`, if `:configuration` in `dirs`
* `LOGS_DIR`: `logs_dir`, if `:logs` in `dirs`
* `CACHE_DIR`: `cache_dir`, if `:cache` in `dirs`
* `STATE_DIR`: `state_dir`, if `:state` in `dirs`
* `TMP_DIR`: `tmp_dir`, if `:tmp` in `dirs`

You can set additional vars using `env_vars`, e.g.:

```elixir
env_vars: [
  "PORT=8080",
]
```
You can also reference the value of other parameters by name, e.g.:

```elixir
env_vars: [
  ["RELEASE_TMP=", :runtime_dir],
]
```

You can read environment vars from files with `env_files`, e.g.:

```elixir
env_files: [
  ["-", :deploy_dir, "/etc/environment"],
  ["-", :configuration_dir, "environment"],
  ["-", :runtime_dir, "environment"],
],
```

The "-" at the beginning makes the file optional; the system will start without it.
Later values override earlier values, so you can set defaults which get
overridden in the local or runtime environment.


### Runtime dirs

The release scripts may need to write temp files and log files, e.g., when
generating the application config files. By default, they do this under
the release dir, e.g., `/srv/foo/current/tmp`.

For security, it's better to deploy the app using a different user account from
the one that the app runs under, with the source files read only. This makes
it harder for an attacker to make changes to the source and then have the app
run them.

In that case, we need to set an environment var which tells the release
startup scripts where they can write files. For Mix releases, that is
`RELEASE_TMP` and for Distillery it is `RELEASE_MUTABLE_DIR`, e.g.:

```elixir
env_vars: [
  {"RELEASE_TMP=", :runtime_dir},
]
```

By default systemd will delete the runtime directory when restarting the app.
This can be annoying when debugging startup issues. You can set
`runtime_directory_preserve` to `restart` or `yes` (see
[RuntimeDirectoryPreserve](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RuntimeDirectoryPreserve=)).

### Starting and restarting

The following variables set systemd variables:

`service_type`: `:simple | :exec | :notify | :forking`. systemd
[Type](https://www.freedesktop.org/software/systemd/man/systemd.service.html#Type=), default `:simple`.

Modern applications don't fork, they run in the foreground and rely on the
supervisor to manage them as a daemon. This is done by setting `service_type`
to `:simple` or `:exec`. Note that in `simple` mode, systemd doesn't actually
check if the app started successfully, it just continues starting other units.
If something depends on your app being up, `:exec` may be better.

Set `service_type` to `:forking`, and the library sets `pid_file` to
`#{runtime_directory}/#{app_name}.pid` and sets the `PIDFILE` env var to tell
the boot scripts where it is.

The Erlang VM runs pretty well in foreground mode, but traditionally runs as
as a standard Unix-style daemon, so forking might be better. Systemd
expects foregrounded apps to die when their pipe closes. See
https://elixirforum.com/t/systemd-cant-shutdown-my-foreground-app-cleanly/14581/2

`restart_method`: `:systemctl | :systemd_flag | :touch`, default `:systemctl`

Set this to `:systemd_flag`, and the library will generate an additional
unit file which watches for changes to a flag file and restarts the
main unit. This allows updates to be pushed to the target machine by an
unprivileged user account which does not have permissions to restart
processes. Touch the file `#{flags_dir}/restart.flag` and systemd will
restart the unit.

`working_dir`: Current working dir for app. systemd
[WorkingDirectory](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#WorkingDirectory=),
default `current_dir`.

`limit_nofile`: Limit on open files, systemd
[LimitNOFILE](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#LimitCPU=),
default 65535.

`umask`: Process umask, systemd
[UMask](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#UMask=),
default "0027". Note that this is octal, so it needs to be a string.

`restart_sec`: Time in seconds to wait between restarts, systemd
[RestartSec](https://www.freedesktop.org/software/systemd/man/systemd.service.html#RestartSec=),
default 100ms.

`syslog_identifier`: Logging name, systemd
[SyslogIdentifier](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#SyslogIdentifier=),
default `service_name`


## `ExecStartPre` scripts

Scripts specified in `exec_start_pre` (systemd
[ExecStartPre](https://www.freedesktop.org/software/systemd/man/systemd.service.html#ExecStartPre=)])
run before the main `ExecStart` script runs, e.g.:

```elixir
exec_start_pre: [
  ["!", :deploy_dir, "/bin/deploy-sync-config-s3"]
]
```

This runs the `deploy-sync-config-s3` script from `mix_deploy`, which
copies config files from an S3 bucket into `/etc/foo`. By default,
scripts run as the same user and group as the main script. Putting
`!` in front makes the script run with [elevated
privileges](https://www.freedesktop.org/software/systemd/man/systemd.service.html#ExecStart=),
allowing it to write config to `/etc/foo` even if the main user account cannot for security reasons.

#### ExecStart wrapper script

Instead of running the main `ExecStart` script directly, you can run a shell script
which sets up the environment, then runs the main script with `exec`.
Set `exec_start_wrap` to the name of the script, e.g.
`deploy-runtime-environment-wrap` from `mix_deploy`.

In Elixir 1.9+ releases you can use `env.sh`, but this runs earlier
with elevated permissions, so a wrapper script may still be useful.

#### Runtime environment service

You can run your own separate service to configure the runtime environment
before the app runs.  Set `runtime_environment_service_script` to a script such
as `deploy-runtime-environment-file` from `mix_deploy`. This library will
create a `#{service_name}-runtime-environment.service` unit and make it a
systemd runtime dependency of the app.

### Runtime dependencies

Systemd starts units in parallel when possible. To enforce ordering, set
`unit_after_targets` to the names of systemd units that this unit depends on.
For example, if this unit should run after cloud-init to get [runtime network
information](https://cloudinit.readthedocs.io/en/latest/topics/network-config.html#network-configuration-outputs),
set:

```elixir
unit_after_targets: [
  "cloud-init.target"
]
```

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


## Distillery

Distillery has largely been replaced by Elixir native releases.
This library works fine with it, though. `exec_start_pre` scripts
are particularly useful in the absence of `env.sh`.

Configure the library by setting `release_system: :distillery`, e.g..

```elixir
config :mix_systemd,
  release_system: :distillery,
  exec_start_pre: [
    # Run script as root before starting
    ["!", :deploy_dir, "/bin/deploy-sync-config-s3"]
  ],
  dirs: [
    :configuration,
    :runtime,
  ],
  runtime_directory_preserve: "yes",
  env_vars: [
    # Use /run/foo for temp files
    ["RELEASE_MUTABLE_DIR=", :runtime_dir],
    # expand $CONFIGURATION_DIR in config files
    REPLACE_OS_VARS=true,
  ]
```

Set up
[config providers](https://hexdocs.pm/distillery/Mix.Releases.Config.Providers.Elixir.html)
in `rel/config.exs`:

```elixir
environment :prod do
  set config_providers: [
    {Mix.Releases.Config.Providers.Elixir, ["${CONFIGURATION_DIR}/config.exs"]}
  ]
end
```

This reads files in Elixir config format. Instead of including your
`prod.secret.exs` file in `prod.exs`, you can copy it to the server separately,
and it will be read at startup.

The [TOML configuration provider](https://github.com/bitwalker/toml-elixir) works similarly:

```elixir
environment :prod do
  set config_providers: [
    {Toml.Provider, [path: "${CONFIGURATION_DIR}/config.toml"]},
  ]
end
```

Add the TOML config provider to `mix.exs`:

```elixir
{:toml_config_provider, "~> 0.2.0"}
```

You can generate a file under the release with an overlay in
`rel/config.exs`, e.g.:

```elixir
environment :prod do
  set overlays: [
    {:mkdir, "etc"},
    {:copy, "rel/etc/environment", "etc/environment"},
    # {:template, "rel/etc/environment", "etc/environment"}
  ]
end
```

That results in a file that would be read by:

```elixir
env_files: [
  ["-", :current_dir, "/etc/environment"],
],
```

Documentation is here: https://hexdocs.pm/mix_systemd

This project uses the Contributor Covenant version 2.1. Check [CODE_OF_CONDUCT.md](/CODE_OF_CONDUCT.md) for more information.

# Contacts

I am `jakemorrison` on on the Elixir Slack and Discord, `reachfh` on Freenode
`#elixir-lang` IRC channel. Happy to chat or help with your projects.
