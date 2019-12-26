# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :mix_systemd, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:mix_systemd, :key)
#
# You can also configure a 3rd-party app:
#
#     config :logger, level: :info
#

config :mix_systemd,
  app_user: "app",
  app_group: "app",
  exec_start_pre: [
    "!/srv/app/bin/deploy-sync-config-s3"
  ],
  dirs: [
    :runtime,       # App runtime files which may be deleted between runs, /run/#{ext_name}
    :configuration, # App configuration, e.g. db passwords, /etc/#{ext_name}
    # :state,         # App data or state persisted between runs, /var/lib/#{ext_name}
    # :cache,         # App cache files which can be deleted, /var/cache/#{ext_name}
    # :logs,          # App external log files, not via journald, /var/log/#{ext_name}
    # :tmp,           # App temp files, /var/tmp/#{ext_name}
  ],
  runtime_directory_preserve: "yes",
  env_vars: [
    "PORT=8080",
    {"RELEASE_TMP", :runtime_dir},
  ]

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"
