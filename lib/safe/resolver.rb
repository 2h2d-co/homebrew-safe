# frozen_string_literal: true

require "set"
require_relative "config"
require_relative "date_filter"
require_relative "ghcr_client"
require_relative "cask_date"
require_relative "version_info"
require_relative "formula_history"

module Safe
  class Resolver
    Candidate = Struct.new(
      :item, :type, :installed_version, :target_version, :latest_version,
      :target_publication_date, :publication_date, :before_value, :cutoff, :safe, :date_unknown, :no_cutoff,
      :upgrade_commit_sha, :upgrade_source_path,
      keyword_init: true,
    )

    def initialize(args:, config:)
      @args = args
      @config = config
    end

    # Returns Array[Candidate]
    def resolve
      candidates = []

      if @args.formula?
        candidates.concat(resolve_formulae)
      elsif @args.cask?
        candidates.concat(resolve_casks)
      elsif @args.named.present?
        # Mixed named args: partition into formulae and casks
        formulae, casks = @args.named.to_resolved_formulae_to_casks
        candidates.concat(resolve_formulae(formulae))
        candidates.concat(resolve_casks(casks))
      else
        candidates.concat(resolve_formulae)
        candidates.concat(resolve_casks)
      end

      candidates
    end

    private

    def resolve_formulae(formulae = nil)
      formulae ||= if @args.named.present? && @args.formula?
        @args.named.to_resolved_formulae
      else
        Formula.installed
      end

      formulae.select { |f| f.outdated? }.reject { |f| f.pinned? }.filter_map do |f|
        if f.head? && !f.stable
          Homebrew.opoo "#{f.full_name}: HEAD-only install, skipping"
          next
        end

        latest = f.latest_formula
        latest_version = latest.pkg_version.to_s
        installed_version = Safe::VersionInfo.formula_installed_version(f)

        cli_before = @args.before
        before_value = @config.resolve_before(type: :formula, full_name: f.full_name, cli_before: cli_before)

        publication_date = Safe::GhcrClient.publication_date(latest)
        date_unknown = publication_date.nil?

        cutoff = before_value ? Safe::DateFilter.parse_cutoff(before_value) : nil
        if before_value && cutoff.nil?
          Homebrew.opoo "#{f.full_name}: invalid 'before' value '#{before_value}', skipping"
          next
        end
        no_cutoff = cutoff.nil? && !date_unknown

        target_version = nil
        target_publication_date = nil
        upgrade_commit_sha = nil
        upgrade_source_path = nil

        is_safe = if date_unknown || cutoff.nil?
          false
        elsif Safe::DateFilter.safe?(publication_date, cutoff)
          target_version = latest_version
          target_publication_date = publication_date
          true
        else
          history = Safe::FormulaHistory.new
          historical_target = history.latest_safe_intermediate(
            formula: f,
            installed_versions: installed_versions(installed_version),
            latest_version: latest_version,
            cutoff: cutoff,
          )

          if historical_target
            target_version = historical_target.version
            target_publication_date = historical_target.publication_date
            upgrade_commit_sha = historical_target.commit_sha
            upgrade_source_path = historical_target.path
            true
          else
            false
          end
        end

        Candidate.new(
          item: f,
          type: :formula,
          installed_version: installed_version,
          target_version: target_version,
          latest_version: latest_version,
          target_publication_date: target_publication_date,
          publication_date: publication_date,
          before_value: before_value,
          cutoff: cutoff,
          safe: is_safe,
          date_unknown: date_unknown,
          no_cutoff: no_cutoff,
          upgrade_commit_sha: upgrade_commit_sha,
          upgrade_source_path: upgrade_source_path,
        )
      end
    end

    def resolve_casks(casks = nil)
      require "cask/caskroom"

      casks ||= if @args.named.present? && @args.cask?
        @args.named.to_casks
      else
        Cask::Caskroom.casks
      end

      greedy = @args.greedy?
      greedy_latest = @args.respond_to?(:greedy_latest?) ? @args.greedy_latest? : false
      greedy_auto_updates = @args.respond_to?(:greedy_auto_updates?) ? @args.greedy_auto_updates? : false

      results = []
      seen = Set.new
      outdated = casks.select { |c|
        c.outdated?(greedy: greedy, greedy_latest: greedy_latest, greedy_auto_updates: greedy_auto_updates)
      }

      outdated.each do |c|
        if Safe::CaskDate.rate_limited?
          Homebrew.opoo "GitHub API rate limited. Authenticate with `gh auth login` or set HOMEBREW_GITHUB_API_TOKEN to continue cask date lookups."
          break
        end

        seen << c

        installed_version = c.installed_version.to_s
        latest_version = c.version.to_s

        cli_before = @args.before
        before_value = @config.resolve_before(type: :cask, full_name: c.full_name, cli_before: cli_before)

        publication_date = Safe::CaskDate.last_updated(c)
        date_unknown = publication_date.nil?

        cutoff = before_value ? Safe::DateFilter.parse_cutoff(before_value) : nil
        if before_value && cutoff.nil?
          Homebrew.opoo "#{c.full_name}: invalid 'before' value '#{before_value}', skipping"
          next
        end
        no_cutoff = cutoff.nil? && !date_unknown
        is_safe = if date_unknown || cutoff.nil?
          false
        else
          Safe::DateFilter.safe?(publication_date, cutoff)
        end

        results << Candidate.new(
          item: c,
          type: :cask,
          installed_version: installed_version,
          target_version: is_safe ? latest_version : nil,
          latest_version: latest_version,
          target_publication_date: is_safe ? publication_date : nil,
          publication_date: publication_date,
          before_value: before_value,
          cutoff: cutoff,
          safe: is_safe,
          date_unknown: date_unknown,
          no_cutoff: no_cutoff,
          upgrade_commit_sha: nil,
          upgrade_source_path: nil,
        )
      end

      # Collect remaining casks after rate limit as date_unknown
      if Safe::CaskDate.rate_limited?
        outdated.reject { |c| seen.include?(c) }.each do |c|
          results << Candidate.new(
            item: c,
            type: :cask,
            installed_version: c.installed_version.to_s,
            target_version: nil,
            latest_version: c.version.to_s,
            target_publication_date: nil,
            publication_date: nil,
            before_value: nil,
            cutoff: nil,
            safe: false,
            date_unknown: true,
            no_cutoff: false,
            upgrade_commit_sha: nil,
            upgrade_source_path: nil,
          )
        end
      end

      results
    end

    def installed_versions(installed_version)
      installed_version.to_s.split(",").map(&:strip).reject(&:empty?)
    end
  end
end
