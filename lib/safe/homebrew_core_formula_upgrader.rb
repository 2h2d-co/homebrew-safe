# frozen_string_literal: true

require "fileutils"

require_relative "formula_history"

module Safe
  class HomebrewCoreFormulaUpgrader
    def initialize(runner:, brew_file:)
      @runner = runner
      @brew_file = brew_file
      @history = Safe::FormulaHistory.new
    end

    def upgrade!(candidate)
      return upgrade_latest!(candidate) unless intermediate_candidate?(candidate)

      tap_path = File.join(HOMEBREW_LIBRARY.to_s, "Taps", "homebrew", "homebrew-core")
      tap_was_installed = File.directory?(tap_path)
      formula_path = File.join(tap_path, candidate.upgrade_source_path)
      current_content = nil

      ensure_homebrew_core_tap!(tap_was_installed)

      historical_content = @history.formula_content_at(
        commit_sha: candidate.upgrade_commit_sha,
        path: candidate.upgrade_source_path,
      )
      raise "Failed to fetch historical formula for #{candidate.item.full_name}@#{candidate.target_version}" if historical_content.nil?

      current_content = File.read(formula_path) if File.exist?(formula_path)
      FileUtils.mkdir_p(File.dirname(formula_path))
      File.write(formula_path, historical_content)

      @runner.safe_system(
        brew_env(use_local_core: true),
        @brew_file,
        "upgrade",
        "--formula",
        candidate.item.full_name,
      )
    ensure
      restore_formula_file(formula_path, current_content) if defined?(formula_path)
      cleanup_homebrew_core_tap(tap_was_installed) if defined?(tap_was_installed)
    end

    private

    def intermediate_candidate?(candidate)
      candidate.type == :formula &&
        candidate.target_version &&
        candidate.latest_version &&
        candidate.target_version != candidate.latest_version &&
        candidate.upgrade_commit_sha &&
        candidate.upgrade_source_path
    end

    def upgrade_latest!(candidate)
      @runner.safe_system(
        brew_env,
        @brew_file,
        "upgrade",
        "--formula",
        candidate.item.full_name,
      )
    end

    def ensure_homebrew_core_tap!(tap_was_installed)
      return if tap_was_installed

      @runner.safe_system(
        brew_env,
        @brew_file,
        "tap",
        "--force",
        "homebrew/core",
      )
    end

    def cleanup_homebrew_core_tap(tap_was_installed)
      return if tap_was_installed

      @runner.safe_system(
        brew_env,
        @brew_file,
        "untap",
        "homebrew/core",
      )
    rescue ErrorDuringExecution
      nil
    end

    def restore_formula_file(formula_path, current_content)
      if current_content.nil?
        File.delete(formula_path) if File.exist?(formula_path)
      else
        File.write(formula_path, current_content)
      end
    end

    def brew_env(use_local_core: false)
      env = { "HOMEBREW_NO_AUTO_UPDATE" => "1" }
      env["HOMEBREW_NO_INSTALL_FROM_API"] = "1" if use_local_core
      env
    end
  end
end
