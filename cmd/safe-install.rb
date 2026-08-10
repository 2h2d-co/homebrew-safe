#!/usr/bin/env ruby
# frozen_string_literal: true

require "abstract_command"
require "formula"

require_relative "../lib/safe/config"
require_relative "../lib/safe/resolver"
require_relative "../lib/safe/date_filter"
require_relative "../lib/safe/auto_update"
require_relative "../lib/safe/homebrew_core_formula_upgrader"

module Homebrew
  module Cmd
    class SafeInstall < AbstractCommand
      cmd_args do
        description <<~EOS
          Install formulae at the newest versions that pass the release date
          safety gate. Versions released too recently are skipped.
        EOS
        flag   "--before=",
               description: "Cutoff: only install versions older than this (e.g. 7d, 30d, 2026-01-01)."
        switch "-n", "--dry-run",
               description: "Show what would be installed without installing."
        named_args [:formula], min: 1
      end

      def run
        Safe::AutoUpdate.run_if_needed!(runner: self, brew_file: HOMEBREW_BREW_FILE, command: "safe-install")

        config = Safe::Config.new
        validate_cutoff!(config)

        formulae = args.named.to_resolved_formulae
        installed = formulae.select(&:any_version_installed?)
        unless installed.empty?
          names = installed.map(&:full_name).join(", ")
          odie "Already installed: #{names}. Use `brew safe-upgrade` for installed formulae."
        end

        candidates = Safe::Resolver.new(args: args, config: config).resolve_formula_install(formulae)
        safe = candidates.select(&:safe)
        too_new = candidates.reject { |candidate| candidate.safe || candidate.date_unknown || candidate.no_cutoff }
        unknown = candidates.select(&:date_unknown)
        no_cutoff = candidates.select(&:no_cutoff)

        if args.dry_run?
          print_candidates("Would install", safe)
          print_skipped(too_new, unknown, no_cutoff)
          return
        end

        if safe.empty?
          ohai "Nothing safe to install."
          print_skipped(too_new, unknown, no_cutoff)
          return
        end

        upgrader = Safe::HomebrewCoreFormulaUpgrader.new(runner: self, brew_file: HOMEBREW_BREW_FILE)
        result = upgrader.install_all(safe)

        puts
        ohai "Summary"
        puts "Installed: #{result.upgraded.size}"
        print_failures(result.failures)
        print_skipped(too_new, unknown, no_cutoff)

        raise result.failures.first.error if result.failures.any?
      rescue Safe::Config::ConfigError => e
        odie e.message
      end

      private

      def validate_cutoff!(config)
        before_value = args.before || config.global_before
        odie <<~EOS.chomp unless before_value || config.has_any_per_item_before?
          No safety cutoff configured. Set a global 'before' in ~/.config/brew-safe/config.yaml:

            before: "30d"

          Or pass --before=<duration> (e.g. --before=30d, --before=2026-01-01).
        EOS

        return unless before_value
        return if Safe::DateFilter.parse_cutoff(before_value)

        odie "Invalid --before value: #{before_value}. Supported: 7d, 30d, 6m, 1y, 2026-01-01, 2026-01-01T00:00:00Z"
      end

      def print_candidates(heading, candidates)
        if candidates.empty?
          ohai "Nothing safe to install."
          return
        end

        ohai heading
        candidates.each do |candidate|
          target_date = candidate.target_publication_date || candidate.publication_date
          latest = if candidate.target_version != candidate.latest_version
            "; latest: #{candidate.latest_version} released #{candidate.publication_date&.split("T")&.first}"
          else
            ""
          end
          puts "#{candidate.item.full_name} -> #{candidate.target_version} " \
               "(released #{target_date&.split("T")&.first}#{latest})"
        end
      end

      def print_skipped(too_new, unknown, no_cutoff)
        print_skipped_group("Skipped (too new)", too_new)
        print_skipped_group("Skipped (date unknown)", unknown)
        print_skipped_group("Skipped (no cutoff configured)", no_cutoff)
      end

      def print_skipped_group(heading, candidates)
        return if candidates.empty?

        puts
        ohai "#{heading}: #{candidates.size}"
        candidates.each do |candidate|
          puts "  #{candidate.item.full_name} -> #{candidate.latest_version}"
        end
      end

      def print_failures(failures)
        return if failures.empty?

        puts
        ohai "Failed: #{failures.size}"
        failures.each do |failure|
          message = failure.error.message.to_s.gsub("\n", "\n    ")
          puts "  #{failure.candidate.item.full_name}: #{message}"
        end
      end
    end
  end
end
