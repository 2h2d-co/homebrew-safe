# frozen_string_literal: true

require "abstract_command"
require "formula"
require "json"
require "cask/caskroom"

require_relative "../lib/safe/config"
require_relative "../lib/safe/resolver"
require_relative "../lib/safe/date_filter"
require_relative "../lib/safe/auto_update"
require_relative "../lib/safe/version_info"

module Homebrew
  module Cmd
    class SafeOutdated < AbstractCommand
      cmd_args do
        description <<~EOS
          List outdated formulae and casks that are safe to upgrade based on
          release date. Versions released too recently are filtered out.
        EOS
        flag   "--before=",
               description: "Cutoff: only show versions older than this (e.g. 7d, 30d, 2026-01-01)."
        switch "--formula", "--formulae",
               description: "Only list outdated formulae."
        switch "--cask", "--casks",
               description: "Only list outdated casks."
        switch "--json",
               description: "Print output in JSON format."
        switch "-v", "--verbose",
               description: "Show versions, release dates, age, and items that are too new or date-unknown."
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
        Safe::AutoUpdate.run_if_needed!(runner: self, brew_file: HOMEBREW_BREW_FILE, command: "safe-outdated")

        config = Safe::Config.new
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

        pinned = pinned_formulae
        safe = candidates.select(&:safe)
        too_new = candidates.reject { |c| c.safe || c.date_unknown || c.no_cutoff }
        unknown = candidates.select(&:date_unknown)
        no_cutoff = candidates.select { |c| c.no_cutoff }

        if args.json?
          print_json(safe, too_new, unknown, no_cutoff, pinned)
        elsif verbose_output?
          print_verbose(config, safe, too_new, unknown, no_cutoff, pinned)
        else
          print_default(safe)
        end
      rescue Safe::Config::ConfigError => e
        odie e.message
      end

      private

      def pinned_formulae
        return [] if args.cask?

        formulae = if args.named.present?
          if args.formula?
            args.named.to_resolved_formulae
          else
            # Mixed args: partition and only use the formula portion
            f, _ = args.named.to_resolved_formulae_to_casks
            f
          end
        else
          Formula.installed
        end
        formulae.select(&:pinned?)
      end

      def print_default(safe)
        safe.each do |c|
          date = safe_publication_date(c)
          date_info = date ? ", released #{date.split("T").first}" : ""
          puts "#{c.item.full_name} (#{c.installed_version} -> #{target_version(c)}#{date_info})"
        end
      end

      def print_verbose(config, safe, too_new, unknown, no_cutoff, pinned)
        header = verbose_header(config)

        if safe.any?
          ohai header
          safe.each do |c|
            cutoff = cutoff_annotation(c, config)
            label = "#{c.item.full_name}#{cutoff}"
            if intermediate_target?(c)
              safe_date = safe_publication_date(c)
              latest_date = c.publication_date
              safe_age = safe_date ? Safe::DateFilter.age_description(safe_date) : ""
              latest_age = latest_date ? Safe::DateFilter.age_description(latest_date) : ""
              puts "#{label} #{c.installed_version} -> #{target_version(c)} (released #{safe_date&.split("T")&.first}, #{safe_age}; latest: #{c.latest_version} released #{latest_date&.split("T")&.first}, #{latest_age})"
            else
              date = safe_publication_date(c)
              age = date ? Safe::DateFilter.age_description(date) : ""
              puts "#{label} #{c.installed_version} -> #{target_version(c)} (released #{date&.split("T")&.first}, #{age})"
            end
          end
        end

        if too_new.any?
          puts if safe.any?
          ohai "Too new"
          too_new.each do |c|
            age = c.publication_date ? Safe::DateFilter.age_description(c.publication_date) : ""
            date = c.publication_date ? c.publication_date.split("T").first : ""
            puts "#{c.item.full_name} #{c.installed_version} -> #{c.latest_version} (released #{date}, #{age})"
          end
        end

        if unknown.any?
          puts if safe.any? || too_new.any?
          ohai "Date unknown (skipped)"
          unknown.each do |c|
            puts "#{c.item.full_name} #{c.installed_version} -> #{c.latest_version}"
          end
        end

        if no_cutoff.any?
          puts if safe.any? || too_new.any? || unknown.any?
          ohai "No cutoff configured (skipped)"
          no_cutoff.each do |c|
            puts "#{c.item.full_name} #{c.installed_version} -> #{c.latest_version}"
          end
        end

        if pinned.any?
          puts if safe.any? || too_new.any? || unknown.any? || no_cutoff.any?
          ohai "Pinned (skipped)"
          pinned.each do |f|
            latest = f.latest_formula
            installed = Safe::VersionInfo.formula_installed_version(f)
            puts "#{f.full_name} #{installed} -> #{latest.pkg_version}"
          end
        end
      end

      def print_json(safe, too_new, unknown, no_cutoff, pinned)
        data = {
          safe: safe.map { |c| candidate_to_hash(c) },
          too_new: too_new.map { |c| candidate_to_hash(c) },
          date_unknown: unknown.map { |c| candidate_to_hash(c) },
          no_cutoff: no_cutoff.map { |c| candidate_to_hash(c) },
          pinned: pinned.map { |f| { name: f.full_name, installed: Safe::VersionInfo.formula_installed_version(f), latest: f.latest_formula.pkg_version.to_s } },
        }
        puts JSON.pretty_generate(data)
      end

      def candidate_to_hash(c)
        {
          name: c.item.full_name,
          type: c.type.to_s,
          installed: c.installed_version,
          target: c.target_version,
          target_publication_date: c.target_publication_date,
          latest: c.latest_version,
          latest_publication_date: c.publication_date,
          before: c.before_value,
          safe: c.safe,
        }
      end

      def verbose_header(config)
        return "Safe to upgrade (default before: #{config.global_before})" if config.global_before
        return "Safe to upgrade (before: #{args.before})" if args.before

        "Safe to upgrade"
      end

      def cutoff_annotation(candidate, config)
        effective_before = candidate.before_value
        default_before = config.global_before
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

      def verbose_output?
        args.verbose? || ENV[Safe::AutoUpdate::COMMAND_VERBOSE_ENV] == "1"
      end
    end
  end
end
