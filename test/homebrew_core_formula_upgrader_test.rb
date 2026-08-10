# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "pathname"
require "safe/homebrew_core_formula_upgrader"

class HomebrewCoreFormulaUpgraderTest < Minitest::Test
  Candidate = Struct.new(
    :type,
    :target_version,
    :latest_version,
    :upgrade_commit_sha,
    :upgrade_source_path,
    :item,
    keyword_init: true,
  )

  Item = Struct.new(:full_name, :name, :latest_formula)

  class FakeRunner
    attr_reader :calls

    def initialize(&on_call)
      @calls = []
      @on_call = on_call
    end

    def safe_system(*args)
      @calls << args
      @on_call&.call(*args)
    end
  end

  class FakeHistory
    def initialize(content)
      @content = content
    end

    def formula_content_at(commit_sha:, path:)
      raise "unexpected commit_sha" unless commit_sha == "abc123"
      raise "unexpected path" unless path == "Formula/m/mise.rb"

      @content
    end
  end

  def test_upgrade_installs_historical_formula_file_from_minimal_local_core_path_when_core_is_not_tapped
    Dir.mktmpdir do |dir|
      with_homebrew_library(Pathname(dir)) do
        runner = FakeRunner.new
        upgrader = Safe::HomebrewCoreFormulaUpgrader.new(
          runner: runner,
          brew_file: "/opt/homebrew/bin/brew",
          dependency_checker: ->(_candidate, _formula_path) { [] },
          installed_versions: ->(candidate) { [candidate.target_version] },
        )
        upgrader.instance_variable_set(:@history, FakeHistory.new("class Mise < Formula; end\n"))

        candidate = Candidate.new(
          type: :formula,
          target_version: "2026.4.11",
          latest_version: "2026.4.15",
          upgrade_commit_sha: "abc123",
          upgrade_source_path: "Formula/m/mise.rb",
          item: Item.new("mise"),
        )

        upgrader.upgrade!(candidate)

        formula_path = Pathname(dir)/"Taps/homebrew/homebrew-core/Formula/m/mise.rb"

        assert_equal [[
          {
            "HOMEBREW_NO_AUTO_UPDATE" => "1",
            "HOMEBREW_NO_ASK" => "1",
            "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK" => "1",
          },
          "/opt/homebrew/bin/brew",
          "install",
          "--formula",
          formula_path.to_s,
        ]], runner.calls

        refute formula_path.exist?
        refute formula_path.parent.parent.parent.exist?
      end
    end
  end

  def test_upgrade_restores_existing_formula_file_in_local_core_path
    Dir.mktmpdir do |dir|
      with_homebrew_library(Pathname(dir)) do
        tap_path = Pathname(dir)/"Taps/homebrew/homebrew-core"
        formula_path = tap_path/"Formula/m/mise.rb"
        formula_path.dirname.mkpath
        formula_path.write("class Mise < Formula\n  desc \"current\"\nend\n")

        runner = FakeRunner.new
        upgrader = Safe::HomebrewCoreFormulaUpgrader.new(
          runner: runner,
          brew_file: "/opt/homebrew/bin/brew",
          dependency_checker: ->(_candidate, _formula_path) { [] },
          installed_versions: ->(candidate) { [candidate.target_version] },
        )
        upgrader.instance_variable_set(:@history, FakeHistory.new("class Mise < Formula\n  desc \"historical\"\nend\n"))

        candidate = Candidate.new(
          type: :formula,
          target_version: "2026.4.11",
          latest_version: "2026.4.15",
          upgrade_commit_sha: "abc123",
          upgrade_source_path: "Formula/m/mise.rb",
          item: Item.new("mise"),
        )

        upgrader.upgrade!(candidate)

        assert_equal [[
          {
            "HOMEBREW_NO_AUTO_UPDATE" => "1",
            "HOMEBREW_NO_ASK" => "1",
            "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK" => "1",
          },
          "/opt/homebrew/bin/brew",
          "install",
          "--formula",
          formula_path.to_s,
        ]], runner.calls
        assert_equal "class Mise < Formula\n  desc \"current\"\nend\n", formula_path.read
      end
    end
  end

  def test_upgrade_all_defers_a_formula_until_its_safe_dependency_is_installed
    installed = []
    runner = FakeRunner.new do |*args|
      installed << args.last
    end
    dependency_checker = lambda do |candidate, _formula_path|
      if candidate.item.full_name == "mise" && !installed.include?("usage")
        ["usage"]
      else
        []
      end
    end
    upgrader = Safe::HomebrewCoreFormulaUpgrader.new(
      runner: runner,
      brew_file: "/opt/homebrew/bin/brew",
      dependency_checker: dependency_checker,
      installed_versions: lambda { |candidate|
        installed.include?(candidate.item.full_name) ? [candidate.target_version] : []
      },
    )
    mise = direct_candidate(name: "mise", latest: "2026.8.2")
    usage = direct_candidate(name: "usage", latest: "5.0.0")

    result = upgrader.upgrade_all([mise, usage])

    assert_equal %w[usage mise], result.upgraded.map { |candidate| candidate.item.full_name }
    assert_empty result.failures
    assert_equal %w[usage mise], runner.calls.map(&:last)
  end

  def test_upgrade_all_blocks_a_formula_when_no_safe_dependency_target_exists
    runner = FakeRunner.new
    upgrader = Safe::HomebrewCoreFormulaUpgrader.new(
      runner: runner,
      brew_file: "/opt/homebrew/bin/brew",
      dependency_checker: ->(_candidate, _formula_path) { ["usage"] },
      installed_versions: ->(_candidate) { [] },
    )
    mise = direct_candidate(name: "mise", latest: "2026.8.3")

    result = upgrader.upgrade_all([mise])

    assert_empty result.upgraded
    assert_equal 1, result.failures.size
    assert_instance_of Safe::HomebrewCoreFormulaUpgrader::UnsatisfiedDependenciesError,
                       result.failures.first.error
    assert_empty runner.calls
  end

  def test_upgrade_all_reports_a_failure_when_the_target_version_was_not_installed
    runner = FakeRunner.new
    upgrader = Safe::HomebrewCoreFormulaUpgrader.new(
      runner: runner,
      brew_file: "/opt/homebrew/bin/brew",
      dependency_checker: ->(_candidate, _formula_path) { [] },
      installed_versions: ->(_candidate) { ["1.0.0"] },
    )
    candidate = direct_candidate(name: "usage", latest: "5.1.0")

    result = upgrader.upgrade_all([candidate])

    assert_empty result.upgraded
    assert_equal 1, result.failures.size
    assert_instance_of Safe::HomebrewCoreFormulaUpgrader::UpgradeVerificationError,
                       result.failures.first.error
    assert_equal 1, runner.calls.size
  end

  private

  def direct_candidate(name:, latest:)
    Candidate.new(
      type: :formula,
      target_version: latest,
      latest_version: latest,
      upgrade_commit_sha: nil,
      upgrade_source_path: nil,
      item: Item.new(name, name, name),
    )
  end

  def with_homebrew_library(path)
    Object.send(:remove_const, :HOMEBREW_LIBRARY) if Object.const_defined?(:HOMEBREW_LIBRARY)
    Object.const_set(:HOMEBREW_LIBRARY, path)
    yield
  ensure
    Object.send(:remove_const, :HOMEBREW_LIBRARY) if Object.const_defined?(:HOMEBREW_LIBRARY)
  end
end
