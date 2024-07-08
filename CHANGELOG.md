# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.1] - 2024-07-07
### Changed
- Update libs

## [0.8.0] - 2024-05-29
### Changed
- Allow setting app name in config and set sane default for umbrella apps,
  thanks to @probably-not
- Update library versions
- Add static checks
- Add GitHub Actions CI

## [0.7.5] - 2020-10-07
### Changed
- Update dialyxir version

## [0.7.4] - 2020-10-07
### Changed
- Make output_dir overridable from config, thanks to @yuchunc
- Update dependencies for Elixir 1.11

## [0.7.3] - 2020-02-25
### Changed
- Update docs

## [0.7.1] - 2020-02-12
### Added
- Bring back `env_lang` variable to set `LANG` environment var
- Default LANG to `en_US.utf8` for better compatibility
- Update ex_doc 0.21.2 => 0.21.3 and build all the time

## [0.7.0] - 2020-01-01
### Added
- Support Elixir 1.9 `mix release`
- Support variable references in paths

### Removed
- Removed obsolete option flags
