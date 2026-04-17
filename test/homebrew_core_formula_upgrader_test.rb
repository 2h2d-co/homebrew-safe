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

  Item = Struct.new(:full_name)

  class FakeRunner
    attr_reader :calls

    def initialize
      @calls = []
    end

    def safe_system(*args)
      @calls << args
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

  def test_upgrade_taps_homebrew_core_with_force_when_needed
    Dir.mktmpdir do |dir|
      with_homebrew_library(Pathname(dir)) do
        runner = FakeRunner.new
        upgrader = Safe::HomebrewCoreFormulaUpgrader.new(
          runner: runner,
          brew_file: "/opt/homebrew/bin/brew",
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

        assert_equal [
          { "HOMEBREW_NO_AUTO_UPDATE" => "1" },
          "/opt/homebrew/bin/brew",
          "tap",
          "--force",
          "homebrew/core",
        ], runner.calls[0]

        assert_equal [
          {
            "HOMEBREW_NO_AUTO_UPDATE" => "1",
            "HOMEBREW_NO_INSTALL_FROM_API" => "1",
          },
          "/opt/homebrew/bin/brew",
          "upgrade",
          "--formula",
          "mise",
        ], runner.calls[1]

        assert_equal [
          { "HOMEBREW_NO_AUTO_UPDATE" => "1" },
          "/opt/homebrew/bin/brew",
          "untap",
          "homebrew/core",
        ], runner.calls[2]
      end
    end
  end

  private

  def with_homebrew_library(path)
    Object.send(:remove_const, :HOMEBREW_LIBRARY) if Object.const_defined?(:HOMEBREW_LIBRARY)
    Object.const_set(:HOMEBREW_LIBRARY, path)
    yield
  ensure
    Object.send(:remove_const, :HOMEBREW_LIBRARY) if Object.const_defined?(:HOMEBREW_LIBRARY)
  end
end
