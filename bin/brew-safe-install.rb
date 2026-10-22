#!/usr/bin/env ruby
# frozen_string_literal: true

# Generated from cmd/safe-install.rb by `mise run wrappers`. Do not edit.
#:  * `safe-install` [`--before=`] [`--dry-run`] <formula> [...]
#:
#:  Install formulae at the newest versions that pass the release date
#:  safety gate. Versions released too recently are skipped.
#:
#:        --before                     Cutoff: only install versions older than this
#:                                     (e.g. 7d, 30d, 2026-01-01).
#:    -n, --dry-run                    Show what would be installed without
#:                                     installing.
#:    -d, --debug                      Display any debugging information.
#:    -q, --quiet                      Make some output more quiet.
#:    -v, --verbose                    Make some output more verbose.
#:    -h, --help                       Show this message.
require File.expand_path("../libexec/cmd/safe-install", __dir__)
Homebrew::Cmd::SafeInstall.new.run
