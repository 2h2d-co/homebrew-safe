# frozen_string_literal: true

require "minitest/autorun"
require "safe/version_info"

class VersionInfoTest < Minitest::Test
  Keg = Struct.new(:version)

  class FakeFormula
    attr_reader :pkg_version

    def initialize(outdated_versions:, pkg_version:)
      @outdated_versions = outdated_versions
      @pkg_version = pkg_version
    end

    def outdated_kegs(fetch_head: false)
      raise "unexpected fetch_head" if fetch_head

      @outdated_versions.map { |version| Keg.new(version) }
    end
  end

  def test_formula_installed_version_uses_outdated_kegs
    formula = FakeFormula.new(outdated_versions: %w[2026.4.4], pkg_version: "2026.4.7")

    assert_equal "2026.4.4", Safe::VersionInfo.formula_installed_version(formula)
  end

  def test_formula_installed_version_joins_multiple_outdated_kegs
    formula = FakeFormula.new(outdated_versions: %w[1.0 1.1], pkg_version: "2.0")

    assert_equal "1.0, 1.1", Safe::VersionInfo.formula_installed_version(formula)
  end

  def test_formula_installed_version_falls_back_to_pkg_version
    formula = FakeFormula.new(outdated_versions: [], pkg_version: "2.0")

    assert_equal "2.0", Safe::VersionInfo.formula_installed_version(formula)
  end
end
