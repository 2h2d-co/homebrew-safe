# frozen_string_literal: true

require "fileutils"
require "set"

require_relative "formula_history"

module Safe
  class HomebrewCoreFormulaUpgrader
    Failure = Struct.new(:candidate, :error, keyword_init: true)
    Result = Struct.new(:upgraded, :failures, keyword_init: true)

    class UnsatisfiedDependenciesError < RuntimeError
      attr_reader :dependencies

      def initialize(candidate, dependencies, operation:)
        @dependencies = dependencies
        target_version = candidate.target_version || candidate.latest_version
        super "cannot safely #{operation} #{candidate.item.full_name} at #{target_version}: " \
              "required dependencies are not satisfied: #{dependencies.join(", ")}"
      end
    end

    class UpgradeVerificationError < RuntimeError; end

    def initialize(runner:, brew_file:, dependency_checker: nil, installed_versions: nil)
      @runner = runner
      @brew_file = brew_file
      @history = Safe::FormulaHistory.new
      @dependency_checker = dependency_checker || method(:default_unsatisfied_dependencies)
      @installed_versions = installed_versions || method(:default_installed_versions)
    end

    def upgrade_all(candidates)
      run_all(candidates, action: :upgrade!)
    end

    def install_all(candidates)
      run_all(candidates, action: :install!)
    end

    def upgrade!(candidate)
      install_target!(candidate, operation: "upgrade")
    end

    def install!(candidate)
      install_target!(candidate, operation: "install")
    end

    private

    def run_all(candidates, action:)
      pending = candidates.dup
      upgraded = []
      failures = []

      until pending.empty?
        pending_names = candidate_names(pending)
        deferred = []
        made_progress = false

        pending.each do |candidate|
          begin
            public_send(action, candidate)
            upgraded << candidate
            made_progress = true
          rescue UnsatisfiedDependenciesError => e
            failure = Failure.new(candidate: candidate, error: e)
            if e.dependencies.all? { |dependency| pending_names.include?(dependency) }
              deferred << failure
            else
              failures << failure
              made_progress = true
            end
          rescue StandardError => e
            failures << Failure.new(candidate: candidate, error: e)
            made_progress = true
          end
        end

        break if deferred.empty?

        unless made_progress
          failures.concat(deferred)
          break
        end

        pending = deferred.map(&:candidate)
      end

      Result.new(upgraded: upgraded, failures: failures)
    end

    def install_target!(candidate, operation:)
      if intermediate_candidate?(candidate)
        install_intermediate!(candidate, operation:)
      else
        install_latest!(candidate, operation:)
      end

      verify_target_installed!(candidate)
    end

    def install_intermediate!(candidate, operation:)
      tap_path = local_homebrew_core_tap_path
      tap_was_installed = File.directory?(tap_path)
      formula_path = File.join(tap_path, candidate.upgrade_source_path)
      current_content = nil

      historical_content = @history.formula_content_at(
        commit_sha: candidate.upgrade_commit_sha,
        path: candidate.upgrade_source_path,
      )
      raise "Failed to fetch historical formula for #{candidate.item.full_name}@#{candidate.target_version}" if historical_content.nil?

      current_content = File.read(formula_path) if File.exist?(formula_path)
      # Avoid `brew tap --force homebrew/core`, which clones the full tap.
      # Instead, materialize just the historical formula file under the local
      # `homebrew/core` path and install that file directly. This preserves the
      # historical bottle block while still allowing dependencies to resolve via
      # the Homebrew API on untapped-core installs.
      prepare_local_homebrew_core_formula_path(formula_path)
      File.write(formula_path, historical_content)

      ensure_dependencies_satisfied!(candidate, formula_path, operation:)
      @runner.safe_system(
        brew_env,
        @brew_file,
        "install",
        "--formula",
        formula_path,
      )
    ensure
      restore_formula_file(formula_path, current_content) if defined?(formula_path)
      cleanup_local_homebrew_core_formula_path(formula_path, tap_was_installed) if defined?(formula_path) && defined?(tap_was_installed)
    end

    def intermediate_candidate?(candidate)
      candidate.type == :formula &&
        candidate.target_version &&
        candidate.latest_version &&
        candidate.target_version != candidate.latest_version &&
        candidate.upgrade_commit_sha &&
        candidate.upgrade_source_path
    end

    def install_latest!(candidate, operation:)
      ensure_dependencies_satisfied!(candidate, nil, operation:)
      @runner.safe_system(
        brew_env,
        @brew_file,
        operation,
        "--formula",
        candidate.item.full_name,
      )
    end

    def ensure_dependencies_satisfied!(candidate, formula_path, operation:)
      dependencies = @dependency_checker.call(candidate, formula_path).map(&:to_s).uniq
      return if dependencies.empty?

      raise UnsatisfiedDependenciesError.new(candidate, dependencies, operation:)
    end

    def default_unsatisfied_dependencies(candidate, formula_path)
      require "formula_installer"
      require "formulary"

      formula = if formula_path
        Formulary.factory(formula_path)
      else
        candidate.item.latest_formula
      end

      installer = FormulaInstaller.new(formula)
      installer.fetch_bottle_tab(quiet: true)
      installer.determine_bottle_tab_attributes
      installer.compute_dependencies.map { |dependency| dependency.to_formula.full_name }
    end

    def verify_target_installed!(candidate)
      target_version = (candidate.target_version || candidate.latest_version).to_s
      installed_versions = @installed_versions.call(candidate).map(&:to_s)
      return if installed_versions.include?(target_version)

      installed = installed_versions.empty? ? "none" : installed_versions.join(", ")
      raise UpgradeVerificationError,
            "#{candidate.item.full_name}: expected #{target_version} after upgrade, but installed version is #{installed}"
    end

    def default_installed_versions(candidate)
      candidate.item.installed_kegs.map { |keg| keg.version.to_s }
    end

    def candidate_names(candidates)
      candidates.each_with_object(Set.new) do |candidate, names|
        names << candidate.item.full_name.to_s
        names << candidate.item.name.to_s if candidate.item.respond_to?(:name)
      end
    end

    def local_homebrew_core_tap_path
      File.join(HOMEBREW_LIBRARY.to_s, "Taps", "homebrew", "homebrew-core")
    end

    def prepare_local_homebrew_core_formula_path(formula_path)
      FileUtils.mkdir_p(File.dirname(formula_path))
    end

    def cleanup_local_homebrew_core_formula_path(formula_path, tap_was_installed)
      return if tap_was_installed

      prune_empty_directories(File.dirname(formula_path), stop_at: File.join(HOMEBREW_LIBRARY.to_s, "Taps"))
    end

    def prune_empty_directories(path, stop_at:)
      current = File.expand_path(path)
      stop_at = File.expand_path(stop_at)

      while current.start_with?("#{stop_at}/")
        begin
          Dir.rmdir(current)
        rescue SystemCallError
          break
        end

        current = File.dirname(current)
      end
    end

    def restore_formula_file(formula_path, current_content)
      if current_content.nil?
        File.delete(formula_path) if File.exist?(formula_path)
      else
        File.write(formula_path, current_content)
      end
    end

    def brew_env
      {
        "HOMEBREW_NO_AUTO_UPDATE" => "1",
        "HOMEBREW_NO_ASK" => "1",
        "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK" => "1",
      }
    end
  end
end
