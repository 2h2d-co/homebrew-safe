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
      { "HOMEBREW_NO_AUTO_UPDATE" => "1" }
    end
  end
end
