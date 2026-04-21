# frozen_string_literal: true

require "abstract_command"
require "formula"
require "cask/caskroom"

require_relative "../lib/safe/config"
require_relative "../lib/safe/resolver"
require_relative "../lib/safe/date_filter"
require_relative "../lib/safe/auto_update"
require_relative "../lib/safe/homebrew_core_formula_upgrader"

module Homebrew
  module Cmd
    class SafeUpgrade < AbstractCommand
      cmd_args do
        description <<~EOS
          Upgrade outdated formulae and casks that pass the release date safety gate.
          Versions released too recently are skipped.
        EOS
        flag   "--before=",
               description: "Cutoff: only upgrade versions older than this (e.g. 7d, 30d, 2026-01-01)."
        switch "--formula", "--formulae",
               description: "Only upgrade formulae."
        switch "--cask", "--casks",
               description: "Only upgrade casks."
        switch "-n", "--dry-run",
               description: "Show what would be upgraded without upgrading."
        switch "-v", "--verbose",
               description: "Show detailed output."
        switch "-g", "--greedy",
               description: "Also include outdated casks with `auto_updates true` or `version :latest`."
        switch "--greedy-latest",
               description: "Also include outdated casks with `version :latest`."
        switch "--greedy-auto-updates",
               description: "Also include outdated casks with `auto_updates true`."
        conflicts "--formula", "--cask"
        named_args [:formula, :cask], min: 0
      end

      def run
        Safe::AutoUpdate.run_if_needed!(runner: self, brew_file: HOMEBREW_BREW_FILE, command: "safe-upgrade")

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
        too_new = candidates.reject { |c| c.safe || c.date_unknown || c.no_cutoff }
        unknown = candidates.select(&:date_unknown)
        no_cutoff = candidates.select { |c| c.no_cutoff }

        if args.dry_run?
          print_dry_run(safe, too_new, unknown, no_cutoff)
          return
        end

        if safe.empty?
          ohai "Nothing safe to upgrade."
          print_skipped_summary(too_new, unknown, no_cutoff)
          return
        end

        safe_formulae = safe.select { |c| c.type == :formula }
        direct_formulae = safe_formulae.reject { |c| intermediate_target?(c) }
        historical_formulae = safe_formulae.select { |c| intermediate_target?(c) }
        safe_casks = safe.select { |c| c.type == :cask }.map { |c| c.item.full_name }

        # Run formula and cask upgrades independently so a failure in one
        # doesn't prevent the other from running
        upgraded = 0
        formula_error = nil
        if direct_formulae.any? || historical_formulae.any?
          begin
            if direct_formulae.any?
              safe_system brew_env, HOMEBREW_BREW_FILE, "upgrade", "--formula", *direct_formulae.map { |c| c.item.full_name }
              upgraded += direct_formulae.size
            end

            if historical_formulae.any?
              upgrader = Safe::HomebrewCoreFormulaUpgrader.new(runner: self, brew_file: HOMEBREW_BREW_FILE)
              historical_formulae.each do |candidate|
                upgrader.upgrade!(candidate)
                upgraded += 1
              end
            end
          rescue ErrorDuringExecution => e
            formula_error = e
          end
        end

        cask_error = nil
        if safe_casks.any?
          begin
            safe_system brew_env, HOMEBREW_BREW_FILE, "upgrade", "--cask", *safe_casks
            upgraded += safe_casks.size
          rescue ErrorDuringExecution => e
            cask_error = e
          end
        end

        puts
        ohai "Summary"
        puts "Upgraded: #{upgraded}#{" (some failures)" if formula_error || cask_error}"
        print_skipped_summary(too_new, unknown, no_cutoff)

        if formula_error && cask_error
          onoe cask_error.message
          raise formula_error
        end
        raise formula_error if formula_error
        raise cask_error if cask_error
      rescue Safe::Config::ConfigError => e
        odie e.message
      end

      private

      def print_dry_run(safe, too_new, unknown, no_cutoff)
        if safe.any?
          ohai "Would upgrade"
          safe.each do |c|
            cutoff = cutoff_annotation(c)
            label = "#{c.item.full_name}#{cutoff}"
            if intermediate_target?(c)
              safe_date = safe_publication_date(c)
              latest_date = c.publication_date
              puts "#{label} #{c.installed_version} -> #{target_version(c)} (released #{safe_date&.split("T")&.first}; latest: #{c.latest_version} released #{latest_date&.split("T")&.first})"
            else
              date = safe_publication_date(c)
              date_info = date ? " (released #{date.split("T").first})" : ""
              puts "#{label} #{c.installed_version} -> #{target_version(c)}#{date_info}"
            end
          end
        else
          ohai "Nothing safe to upgrade."
        end

        print_skipped_summary(too_new, unknown, no_cutoff)
      end

      def print_skipped_summary(too_new, unknown, no_cutoff)
        if too_new.any?
          puts
          ohai "Skipped (too new): #{too_new.size}"
          too_new.each do |c|
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

      def safe_publication_date(candidate)
        candidate.target_publication_date || candidate.publication_date
      end

      def intermediate_target?(candidate)
        candidate.target_version && candidate.latest_version && candidate.target_version != candidate.latest_version
      end

      def brew_env
        { "HOMEBREW_NO_AUTO_UPDATE" => "1" }
      end
    end
  end
end
