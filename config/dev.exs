import Config

config :mix_systemd,
  app_user: "app",
  app_group: "app",
  exec_start_pre: [
    ["!", :deploy_dir, "/bin/deploy-sync-config-s3"]
  ],
  dirs: [
    # App runtime files which may be deleted between runs, /run/#{ext_name}
    :runtime,
    # App configuration, e.g. db passwords, /etc/#{ext_name}
    :configuration
    # :state,         # App data or state persisted between runs, /var/lib/#{ext_name}
    # :cache,         # App cache files which can be deleted, /var/cache/#{ext_name}
    # :logs,          # App external log files, not via journald, /var/log/#{ext_name}
    # :tmp,           # App temp files, /var/tmp/#{ext_name}
  ],
  runtime_directory_preserve: "yes",
  env_files: [
    ["!", :deploy_dir, "/etc/environment"],
    ["!", :configuration_dir, "/environment"]
  ],
  env_vars: [
    "PORT=8080",
    ["RELEASE_TMP=", :runtime_dir]
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:file, :line]
