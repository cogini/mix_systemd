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
# config :mix_systemd,
#   runtime_environment_wrap: true,
#   env_vars: [
#     "REPLACE_OS_VARS=true",
#   ]
#
# config :mix_systemd,
#   runtime_environment_service: true,
#   env_vars: [
#     "REPLACE_OS_VARS=true",
#   ]
#
# config :mix_systemd,
#   # Enable restart from flag file
#   restart_flag: true,
#   # Enable chroot
#   chroot: true,
#   # Enable extra restrictions
#   paranoia: true,
#   dirs: [
#     :runtime, # for runtime environment
#     # :configuration, # for app config files
#     # :logs, # for external log file, not journald
#     # :cache, # for app cache files which can be deleted
#     # :state, # for app state persisted between runs
#     # :tmp, # for app temp files
#   ]

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"
