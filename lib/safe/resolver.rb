# frozen_string_literal: true

require_relative "config"
require_relative "date_filter"
require_relative "ghcr_client"
require_relative "cask_date"

module Safe
  class Resolver
    Candidate = Struct.new(
      :item, :type, :installed_version, :latest_version,
      :publication_date, :cutoff, :safe, :date_unknown, :no_cutoff,
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
        installed_version = f.pkg_version.to_s

        cli_before = @args.before
        before_value = @config.resolve_before(type: :formula, full_name: f.full_name, cli_before: cli_before)

        publication_date = Safe::GhcrClient.publication_date(latest)
        date_unknown = publication_date.nil?

        cutoff = before_value ? Safe::DateFilter.parse_cutoff(before_value) : nil
        no_cutoff = cutoff.nil? && !date_unknown
        is_safe = if date_unknown || cutoff.nil?
          false
        else
          Safe::DateFilter.safe?(publication_date, cutoff)
        end

        Candidate.new(
          item: f,
          type: :formula,
          installed_version: installed_version,
          latest_version: latest_version,
          publication_date: publication_date,
          cutoff: cutoff,
          safe: is_safe,
          date_unknown: date_unknown,
          no_cutoff: no_cutoff,
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
      casks.select { |c|
        c.outdated?(greedy: greedy, greedy_latest: greedy_latest, greedy_auto_updates: greedy_auto_updates)
      }.each do |c|
        if Safe::CaskDate.rate_limited?
          Homebrew.opoo "GitHub API rate limited. Set HOMEBREW_GITHUB_API_TOKEN to continue cask date lookups."
          break
        end

        installed_version = c.installed_version.to_s
        latest_version = c.version.to_s

        cli_before = @args.before
        before_value = @config.resolve_before(type: :cask, full_name: c.full_name, cli_before: cli_before)

        publication_date = Safe::CaskDate.last_updated(c)
        date_unknown = publication_date.nil?

        cutoff = before_value ? Safe::DateFilter.parse_cutoff(before_value) : nil
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
          latest_version: latest_version,
          publication_date: publication_date,
          cutoff: cutoff,
          safe: is_safe,
          date_unknown: date_unknown,
          no_cutoff: no_cutoff,
        )
      end
      results
    end
  end
end
