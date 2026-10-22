#!/usr/bin/env ruby
# frozen_string_literal: true

# Generated from cmd/safe-upgrade.rb by `mise run wrappers`. Do not edit.
#:  * `safe-upgrade` [<options>] [<formula>|<cask> ...]
#:
#:  Upgrade installed formulae and casks to versions that pass the release-age
#:  gate. With no arguments, check every installed package. Pinned formulae are
#:  skipped.
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
#:  bottle requires. Passing dependency upgrades are installed first. A
#:  dependency that is not installed, or has no passing upgrade to a required
#:  version, makes the command use an older passing version or skip the formula.
#:  Outdated dependents are not upgraded unless they pass the gate themselves.
#:
#:  After upgrading, the command lists the upgrades it skipped and why.
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
#:        --formula, --formulae        Only upgrade formulae.
#:        --cask, --casks              Only upgrade casks.
#:    -n, --dry-run                    List the upgrades that would run and the ones
#:                                     that would be skipped, without upgrading.
#:    -v, --verbose                    Show detailed output.
#:    -g, --greedy                     Also include outdated casks with
#:                                     `auto_updates true` or `version :latest`.
#:        --greedy-latest              Also include outdated casks with `version
#:                                     :latest`.
#:        --greedy-auto-updates        Also include outdated casks with
#:                                     `auto_updates true`.
#:    -d, --debug                      Display any debugging information.
#:    -q, --quiet                      Make some output more quiet.
#:    -h, --help                       Show this message.
require File.expand_path("../libexec/cmd/safe-upgrade", __dir__)
Homebrew::Cmd::SafeUpgrade.new.run
