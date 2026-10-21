# frozen_string_literal: true

require_relative "dependency_plan"

module Safe
  # Reads a target bottle's runtime dependency requirements through Homebrew's
  # installer, which compares the bottle's minimum versions with installed kegs.
  module FormulaDependencies
    module_function

    # Returns [Safe::DependencyPlan::Requirement] that the installed kegs do not satisfy.
    def unsatisfied(formula)
      require "formula_installer"

      installer = FormulaInstaller.new(formula)
      installer.fetch_bottle_tab(quiet: true)
      installer.determine_bottle_tab_attributes
      installer.compute_dependencies.map do |dependency|
        dependency_formula = dependency.to_formula
        Safe::DependencyPlan::Requirement.new(
          name: dependency_formula.full_name,
          minimum_version: minimum_version(installer.bottle_tab_runtime_dependencies[dependency.name]),
          installed_version: dependency_formula.any_installed_version&.to_s,
        )
      end
    end

    # Loads the candidate's target formula without writing to the Homebrew library.
    def target_formula(candidate, history:)
      return candidate.item.latest_formula unless historical_target?(candidate)

      require "formulary"

      content = history.formula_content_at(commit_sha: candidate.upgrade_commit_sha, path: candidate.upgrade_source_path)
      raise "Failed to fetch historical formula for #{candidate.item.full_name}@#{candidate.target_version}" if content.nil?

      path = Pathname(File.join(HOMEBREW_LIBRARY.to_s, "Taps", "homebrew", "homebrew-core", candidate.upgrade_source_path))
      Formulary.from_contents(candidate.item.name, path, content)
    end

    def historical_target?(candidate)
      candidate.target_version &&
        candidate.target_version != candidate.latest_version &&
        candidate.upgrade_commit_sha &&
        candidate.upgrade_source_path
    end

    # Mirrors FormulaInstaller: the bottle tab records each dependency's version and revision.
    def minimum_version(tab_dependency)
      version = tab_dependency&.fetch("version", nil).to_s
      return nil if version.empty?

      revision = tab_dependency["revision"].to_i
      revision.positive? ? "#{version}_#{revision}" : version
    end
  end
end
