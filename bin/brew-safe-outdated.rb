#!/usr/bin/env ruby
# frozen_string_literal: true

# Generated from cmd/safe-outdated.rb by `mise run wrappers`. Do not edit.
#:  * `safe-outdated` [<options>] [<formula>|<cask> ...]
#:
#:  List installed formulae and casks with an upgrade that passes the
#:  release-age gate. With no arguments, check every installed package.
#:
#:  A version passes the release-age gate when it was published before the cutoff.
#:  If the newest version is too new, the command can use the newest older
#:  Homebrew/core formula or cask version that passes.
#:
#:  The cutoff comes from `--before`, then the package's own `before` in
#:  `~/.config/brew-safe/config.yaml`, then the global `before` in that file.
#:  There is no built-in default. A cutoff is an age such as `7d`, `6m`, or `1y`,
#:  or a date such as `2026-01-01` or `2026-01-01T00:00:00Z`.
#:
#:  A formula upgrade also needs its runtime dependencies at the versions its
#:  bottle requires. Each dependency must be installed at such a version or have
#:  a passing upgrade to one. Otherwise the command uses an older passing version
#:  or reports the formula as blocked by dependencies.
#:
#:  By default, only passing upgrades are listed. Use `--verbose` or `--json` to
#:  also see skipped upgrades: too new, date unknown, no cutoff configured,
#:  blocked by dependencies, and pinned.
#:
#:  A formula's date is when its bottle was published to GHCR. A cask's date is
#:  when the Homebrew commit that added the version was made. Cask lookups use
#:  the GitHub API, so authenticate with `gh auth login` or set
#:  `HOMEBREW_GITHUB_API_TOKEN` to avoid rate limits.
#:
#:  Homebrew is updated first unless `HOMEBREW_NO_AUTO_UPDATE` is set.
#:
#:        --before                     Use this cutoff instead of the configured
#:                                     ones, such as `7d` or `2026-01-01`.
#:        --formula, --formulae        Only check formulae.
#:        --cask, --casks              Only check casks.
#:        --json                       Print every passing and skipped upgrade as
#:                                     JSON, grouped by `safe`,
#:                                     `blocked_by_dependencies`, `too_new`,
#:                                     `date_unknown`, `no_cutoff`, and `pinned`.
#:    -v, --verbose                    Show release dates and ages, the newest
#:                                     version when an older one is used, and
#:                                     skipped upgrades grouped by reason.
#:    -g, --greedy                     Also include outdated casks with
#:                                     `auto_updates true` or `version :latest`.
#:        --greedy-latest              Also include outdated casks with `version
#:                                     :latest`.
#:        --greedy-auto-updates        Also include outdated casks with
#:                                     `auto_updates true`.
#:    -d, --debug                      Display any debugging information.
#:    -q, --quiet                      Make some output more quiet.
#:    -h, --help                       Show this message.
require File.expand_path("../libexec/cmd/safe-outdated", __dir__)
Homebrew::Cmd::SafeOutdated.new.run
