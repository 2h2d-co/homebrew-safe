#!/usr/bin/env ruby
# frozen_string_literal: true

require "abstract_command"
require "system_command"
require "formula"
require "cask/caskroom"

require_relative "../lib/safe/config"
require_relative "../lib/safe/resolver"
require_relative "../lib/safe/date_filter"
require_relative "../lib/safe/auto_update"
require_relative "../lib/safe/candidate_details"
require_relative "../lib/safe/help"
require_relative "../lib/safe/cask_upgrader"
require_relative "../lib/safe/homebrew_core_formula_upgrader"

module Homebrew
  module Cmd
    class SafeUpgrade < AbstractCommand
      cmd_args do
        description <<~EOS
          Upgrade installed formulae and casks to versions that pass the release-age
          gate. With no arguments, check every installed package. Pinned formulae are
          skipped.

          #{Safe::Help::GATE}

          #{Safe::Help::CUTOFF}

          A formula upgrade also needs its runtime dependencies at the versions its
          bottle requires. The command installs missing dependencies and upgrades
          outdated ones first, at versions that pass the gate, even when they are not
          named. It marks the formulae it installs this way as dependencies, so
          `brew autoremove` can remove them once nothing needs them. A dependency
          without a passing version that meets the requirement makes the command use
          an older passing version or skip the formula. Outdated dependents are not
          upgraded unless they pass the gate themselves.

          After upgrading, the command lists the upgrades it skipped and why.

          #{Safe::Help::DATES}

          #{Safe::Help::AUTO_UPDATE}
        EOS
        flag   "--before=",
               description: Safe::Help::BEFORE_OPTION
        switch "--formula", "--formulae",
               description: "Only upgrade formulae."
        switch "--cask", "--casks",
               description: "Only upgrade casks."
        switch "-n", "--dry-run",
               description: "List the upgrades that would run and the ones that would be skipped, " \
                            "without upgrading."
        switch "-v", "--verbose",
               description: "List the planned upgrades before running them, with release dates and ages " \
                            "and the newest version when an older one is used. Also show release dates " \
                            "for skipped upgrades and Homebrew's verification and post-install steps."
        switch "-g", "--greedy",
               description: "Also include outdated casks with `auto_updates true` or `version :latest`."
        switch "--greedy-latest",
               description: "Also include outdated casks with `version :latest`."
        switch "--greedy-auto-updates",
               description: "Also include outdated casks with `auto_updates true`."
        conflicts "--formula", "--cask"
        named_args [:formula, :cask]
      end

      def run
        Safe::AutoUpdate.run_if_needed!(runner: SystemCommand, brew_file: HOMEBREW_BREW_FILE, command: "safe-upgrade")
        Safe::CaskUpgrader.cleanup_stale_temp_taps!(runner: SystemCommand, brew_file: HOMEBREW_BREW_FILE)

        @verbose = Safe::AutoUpdate.command_verbose?(args.verbose?)
        config = Safe::Config.new
        @config = config
        before_value = args.before || config.global_before
        odie <<~EOS.chomp unless before_value || config.has_any_per_item_before?
          No safety cutoff configured. Set a global 'before' in ~/.config/brew-safe/config.yaml:

            before: "30d"

          Or pass --before=<duration> (e.g. --before=30d, --before=2026-01-01).
        EOS

        if before_value
          unless Safe::DateFilter.parse_cutoff(before_value)
            odie "Invalid --before value: #{before_value}. Supported: 7d, 30d, 6m, 1y, 2026-01-01, 2026-01-01T00:00:00Z"
          end
        end

        resolver = Safe::Resolver.new(args: args, config: config)
        candidates = resolver.resolve

        safe = candidates.select(&:safe)
        blocked = candidates.select(&:blocked_dependencies)
        too_new = candidates.reject { |c| c.safe || c.blocked_dependencies || c.date_unknown || c.no_cutoff }
        unknown = candidates.select(&:date_unknown)
        no_cutoff = candidates.select { |c| c.no_cutoff }

        if args.dry_run?
          print_dry_run(safe, blocked, too_new, unknown, no_cutoff)
          return
        end

        if safe.empty?
          ohai "Nothing safe to upgrade."
          print_skipped_summary(blocked, too_new, unknown, no_cutoff)
          return
        end

        if @verbose
          print_planned("Upgrading", safe)
          puts
        end

        safe_formulae = safe.select { |c| c.type == :formula }
        safe_casks = safe.select { |c| c.type == :cask }

        upgraded = 0
        installed = 0
        failures = []

        if safe_formulae.any?
          formula_upgrader = Safe::HomebrewCoreFormulaUpgrader.new(
            runner: SystemCommand,
            brew_file: HOMEBREW_BREW_FILE,
            verbose: @verbose,
          )
          result = formula_upgrader.install_or_upgrade_all(safe_formulae)
          installed += result.upgraded.count { |candidate| candidate.installed_version.nil? }
          upgraded += result.upgraded.count(&:installed_version)
          failures.concat(result.failures.map { |failure| [failure.candidate, failure.error] })
        end

        if safe_casks.any?
          cask_upgrader = Safe::CaskUpgrader.new(runner: SystemCommand, brew_file: HOMEBREW_BREW_FILE, verbose: @verbose)
          safe_casks.each do |candidate|
            begin
              cask_upgrader.upgrade!(candidate)
              upgraded += 1
            rescue StandardError => e
              failures << [candidate, e]
            end
          end
        end

        puts
        ohai "Summary"
        puts "Upgraded: #{upgraded}"
        puts "Installed dependencies: #{installed}" if installed.positive?
        print_failures(failures)
        print_skipped_summary(blocked, too_new, unknown, no_cutoff)

        raise failures.first.last if failures.any?
      rescue Safe::Config::ConfigError => e
        odie e.message
      end

      private

      def print_dry_run(safe, blocked, too_new, unknown, no_cutoff)
        if safe.any?
          print_planned("Would upgrade", safe)
        else
          ohai "Nothing safe to upgrade."
        end

        print_skipped_summary(blocked, too_new, unknown, no_cutoff)
      end

      def print_planned(heading, safe)
        ohai heading
        safe.each do |c|
          label = "#{c.item.full_name}#{cutoff_annotation(c)}"
          if @verbose
            puts Safe::CandidateDetails.upgrade(c, label:)
          else
            date = safe_publication_date(c)
            details = [("released #{date.split("T").first}" if date)]
            if intermediate_target?(c)
              details << "latest: #{c.latest_version} released #{c.publication_date&.split("T")&.first}"
            end
            details << required_by(c)
            details.compact!
            puts "#{label} #{versions(c)}#{" (#{details.join("; ")})" if details.any?}"
          end
        end
      end

      def print_skipped_summary(blocked, too_new, unknown, no_cutoff)
        if blocked.any?
          puts
          ohai "Skipped (blocked by dependencies): #{blocked.size}"
          blocked.each do |c|
            required = c.required_by ? " (required by #{c.required_by.join(", ")})" : ""
            puts "  #{c.item.full_name} #{versions(c)}#{required} requires: #{c.blocked_dependencies.join("; ")}"
          end
        end

        if too_new.any?
          puts
          ohai "Skipped (too new): #{too_new.size}"
          too_new.each do |c|
            next puts("  #{Safe::CandidateDetails.upgrade(c)}") if @verbose

            age = c.publication_date ? Safe::DateFilter.age_description(c.publication_date) : ""
            puts "  #{c.item.full_name} #{c.installed_version} -> #{c.latest_version} (#{age})"
          end
        end

        if unknown.any?
          puts
          ohai "Skipped (date unknown): #{unknown.size}"
          unknown.each do |c|
            puts "  #{c.item.full_name} #{c.installed_version} -> #{c.latest_version}"
          end
        end

        if no_cutoff.any?
          puts
          ohai "Skipped (no cutoff configured): #{no_cutoff.size}"
          no_cutoff.each do |c|
            puts "  #{c.item.full_name} #{c.installed_version} -> #{c.latest_version}"
          end
        end
      end

      def print_failures(failures)
        return if failures.empty?

        puts
        ohai "Failed: #{failures.size}"
        failures.each do |candidate, error|
          message = error.message.to_s.gsub("\n", "\n    ")
          puts "  #{candidate.item.full_name}: #{message}"
        end
      end

      def cutoff_annotation(candidate)
        effective_before = candidate.before_value
        default_before = @config&.global_before
        return "" if effective_before.nil?
        return " [before: #{effective_before}]" if args.before
        return " [before: #{effective_before}]" if default_before.nil?
        return "" if effective_before == default_before

        " [before: #{effective_before}]"
      end

      def target_version(candidate)
        candidate.target_version || candidate.latest_version
      end

      def versions(candidate)
        Safe::CandidateDetails.versions(candidate, target_version(candidate))
      end

      def required_by(candidate)
        "required by #{candidate.required_by.join(", ")}" if candidate.required_by&.any?
      end

      def safe_publication_date(candidate)
        candidate.target_publication_date || candidate.publication_date
      end

      def intermediate_target?(candidate)
        candidate.target_version && candidate.latest_version && candidate.target_version != candidate.latest_version
      end
    end
  end
end
