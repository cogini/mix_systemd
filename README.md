# mix_systemd

Create systemd unit files for Elixir project.

This module provides mix tasks which generate a systemd unit file for
your project. It generates the files under `_project/:env/systemd/lib/systemd/system`.

In addition to the primary systemd unit file, it can optionally generate a systemd
unit which will restart the main unit when a flag file appears or changes.

## Usage

```shell
# Creates revision from current release with MIX_ENV=dev (the default)
mix systemd.init

# Builds a release with MIX_ENV=prod
MIX_ENV=prod mix systemd.generate
```

## Configuration

This module gets its configuration from `mix_systemd` parameters in the mix project, e.g.:

```elixir
def project do
[
  app: :foo,
  version: "0.1.0",
  elixir: "~> 1.6",
  start_permanent: Mix.env() == :prod,
  deps: deps(),
  mix_systemd: [
    restart_flag: true,
  ],
]
end
```

See `lib/mix/tasks/systemd.ex` for configuration defaults.


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mix_systemd` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mix_systemd, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/mix_systemd](https://hexdocs.pm/mix_systemd).

