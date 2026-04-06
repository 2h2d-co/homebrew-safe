# frozen_string_literal: true

require "abstract_command"
require "formula"
require "cask/caskroom"

require_relative "../lib/safe/config"
require_relative "../lib/safe/resolver"
require_relative "../lib/safe/date_filter"

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
        config = Safe::Config.new
        before_value = args.before || config.global_before
        odie <<~EOS.chomp unless before_value || has_any_per_item_config?(config)
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
        too_new = candidates.reject { |c| c.safe || c.date_unknown }
        unknown = candidates.select(&:date_unknown)

        if args.dry_run?
          print_dry_run(safe, too_new, unknown)
          return
        end

        if safe.empty?
          ohai "Nothing safe to upgrade."
          print_skipped_summary(too_new, unknown)
          return
        end

        safe_formulae = safe.select { |c| c.type == :formula }.map { |c| c.item.full_name }
        safe_casks = safe.select { |c| c.type == :cask }.map { |c| c.item.full_name }

        if safe_formulae.any?
          safe_system HOMEBREW_BREW_FILE, "upgrade", *safe_formulae
        end

        if safe_casks.any?
          safe_system HOMEBREW_BREW_FILE, "upgrade", "--cask", *safe_casks
        end

        puts
        ohai "Summary"
        puts "Upgraded: #{safe.size}"
        print_skipped_summary(too_new, unknown)
      end

      private

      def has_any_per_item_config?(config)
        data = config.data
        (data["formula"]&.any? { |_, v| v.is_a?(Hash) && v["before"] }) ||
          (data["cask"]&.any? { |_, v| v.is_a?(Hash) && v["before"] })
      end

      def print_dry_run(safe, too_new, unknown)
        if safe.any?
          ohai "Would upgrade"
          safe.each do |c|
            date_info = c.publication_date ? " (released #{c.publication_date.split("T").first})" : ""
            puts "#{c.item.full_name} #{c.installed_version} -> #{c.latest_version}#{date_info}"
          end
        else
          ohai "Nothing safe to upgrade."
        end

        print_skipped_summary(too_new, unknown)
      end

      def print_skipped_summary(too_new, unknown)
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
      end
    end
  end
end
