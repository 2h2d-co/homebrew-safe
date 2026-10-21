# frozen_string_literal: true

require "minitest/autorun"
require "safe/dependency_plan"

class DependencyPlanTest < Minitest::Test
  Candidate = Struct.new(
    :item, :type, :installed_version, :target_version, :latest_version, :target_publication_date,
    :safe, :date_unknown, :no_cutoff, :upgrade_commit_sha, :upgrade_source_path, :blocked_dependencies,
    keyword_init: true,
  )
  Item = Struct.new(:full_name)
  VersionRef = Struct.new(:version, :publication_date, :commit_sha, :path, keyword_init: true)
  Requirement = Safe::DependencyPlan::Requirement

  def test_keeps_upgrades_whose_dependencies_are_installed
    jq = formula("jq", installed: "1.7", target: "1.8")

    plan(requirements: {}).apply([jq])

    assert jq.safe
    assert_nil jq.blocked_dependencies
  end

  def test_blocks_upgrade_needing_an_uninstalled_dependency_and_its_dependents
    krb5 = formula("krb5", installed: "1.22.2", target: "1.22.2_2")
    libpq = formula("libpq", installed: "18.6", target: "18.6_1")
    requirements = {
      ["krb5", "1.22.2_2"] => [requirement("openssl@4", "4.0.3")],
      ["libpq", "18.6_1"] => [requirement("openssl@4", "4.0.3"), requirement("krb5", "1.22.2_2", installed: "1.22.2")],
    }

    plan(requirements:).apply([krb5, libpq])

    refute krb5.safe
    assert_equal ["openssl@4 >= 4.0.3 (not installed)"], krb5.blocked_dependencies
    refute libpq.safe
    assert_equal [
      "openssl@4 >= 4.0.3 (not installed)",
      "krb5 >= 1.22.2_2 (installed 1.22.2, upgrade blocked)",
    ], libpq.blocked_dependencies
  end

  def test_keeps_upgrade_whose_dependency_is_satisfied_by_a_planned_upgrade
    openssl = formula("openssl@3", installed: "3.6.1", target: "3.6.3")
    curl = formula("curl", installed: "8.1", target: "8.2")
    requirements = { ["curl", "8.2"] => [requirement("openssl@3", "3.6.2", installed: "3.6.1")] }

    plan(requirements:).apply([openssl, curl])

    assert openssl.safe
    assert curl.safe
  end

  def test_installs_need_uninstalled_dependencies_named_in_the_same_install
    usage = formula("usage", installed: nil, target: "2.1")
    mise = formula("mise", installed: nil, target: "2026.10.1")
    node = formula("node", installed: nil, target: "24.1")
    requirements = {
      ["mise", "2026.10.1"] => [requirement("usage", "2.0")],
      ["node", "24.1"] => [requirement("simdjson", "4.0")],
    }

    plan(requirements:).apply([usage, mise, node])

    assert usage.safe
    assert mise.safe
    refute node.safe
    assert_equal ["simdjson >= 4.0 (not installed)"], node.blocked_dependencies
  end

  def test_blocks_upgrade_when_planned_dependency_target_is_below_the_minimum
    openssl = formula("openssl@3", installed: "3.6.1", target: "3.6.2", latest: "3.6.3")
    curl = formula("curl", installed: "8.1", target: "8.2")
    requirements = { ["curl", "8.2"] => [requirement("openssl@3", "3.6.3", installed: "3.6.1")] }

    plan(requirements:).apply([openssl, curl])

    assert openssl.safe
    refute curl.safe
    assert_equal ["openssl@3 >= 3.6.3 (installed 3.6.1, safe target 3.6.2)"], curl.blocked_dependencies
  end

  def test_reports_a_too_new_dependency_upgrade
    libunistring = formula("libunistring", installed: "1.4.2", target: nil, latest: "1.5", safe: false)
    wget = formula("wget", installed: "1.24", target: "1.25")
    requirements = { ["wget", "1.25"] => [requirement("libunistring", "1.5", installed: "1.4.2")] }

    plan(requirements:).apply([libunistring, wget])

    assert_equal ["libunistring >= 1.5 (installed 1.4.2, upgrade too new)"], wget.blocked_dependencies
  end

  def test_falls_back_to_an_older_safe_target_whose_dependencies_are_installed
    krb5 = formula("krb5", installed: "1.22.2", target: "1.22.2_2")
    requirements = {
      ["krb5", "1.22.2_2"] => [requirement("openssl@4", "4.0.3")],
      ["krb5", "1.22.2_1"] => [],
    }
    older = VersionRef.new(version: "1.22.2_1", publication_date: "2026-09-01T00:00:00Z", commit_sha: "abc", path: "Formula/k/krb5.rb")

    plan(requirements:, older_targets: { "krb5" => [older] }).apply([krb5])

    assert krb5.safe
    assert_nil krb5.blocked_dependencies
    assert_equal "1.22.2_1", krb5.target_version
    assert_equal "2026-09-01T00:00:00Z", krb5.target_publication_date
    assert_equal "abc", krb5.upgrade_commit_sha
    assert_equal "Formula/k/krb5.rb", krb5.upgrade_source_path
  end

  def test_reports_the_newest_safe_target_when_every_fallback_is_blocked
    krb5 = formula("krb5", installed: "1.22.2", target: "1.22.2_2")
    requirements = {
      ["krb5", "1.22.2_2"] => [requirement("openssl@4", "4.0.3")],
      ["krb5", "1.22.2_1"] => [requirement("openssl@4", "4.0.0")],
    }
    older = VersionRef.new(version: "1.22.2_1", publication_date: "2026-09-01T00:00:00Z", commit_sha: "abc", path: "Formula/k/krb5.rb")

    plan(requirements:, older_targets: { "krb5" => [older] }).apply([krb5])

    refute krb5.safe
    assert_equal "1.22.2_2", krb5.target_version
    assert_nil krb5.upgrade_commit_sha
    assert_equal ["openssl@4 >= 4.0.3 (not installed)"], krb5.blocked_dependencies
  end

  def test_dependent_falls_back_when_its_dependency_falls_back
    openssl = formula("openssl@3", installed: "3.6.1", target: "3.6.3")
    curl = formula("curl", installed: "8.1", target: "8.2")
    requirements = {
      ["openssl@3", "3.6.3"] => [requirement("zlib", "1.4")],
      ["openssl@3", "3.6.2"] => [],
      ["curl", "8.2"] => [requirement("openssl@3", "3.6.3", installed: "3.6.1")],
      ["curl", "8.1.5"] => [requirement("openssl@3", "3.6.2", installed: "3.6.1")],
    }
    older_targets = {
      "openssl@3" => [VersionRef.new(version: "3.6.2")],
      "curl" => [VersionRef.new(version: "8.1.5")],
    }

    plan(requirements:, older_targets:).apply([openssl, curl])

    assert openssl.safe
    assert_equal "3.6.2", openssl.target_version
    assert curl.safe
    assert_equal "8.1.5", curl.target_version
  end

  def test_requires_the_latest_dependency_version_when_the_bottle_records_no_minimum
    openssl = formula("openssl@3", installed: "3.6.1", target: "3.6.2", latest: "3.6.3")
    curl = formula("curl", installed: "8.1", target: "8.2")
    requirements = { ["curl", "8.2"] => [requirement("openssl@3", nil, installed: "3.6.1")] }

    plan(requirements:).apply([openssl, curl])

    assert_equal ["openssl@3 (latest version) (installed 3.6.1, safe target 3.6.2)"], curl.blocked_dependencies
  end

  def test_blocks_upgrade_when_the_dependency_check_fails
    jq = formula("jq", installed: "1.7", target: "1.8")

    plan(requirements: {}, failures: { "jq" => "manifest unavailable" }).apply([jq])

    refute jq.safe
    assert_equal ["dependency check failed: manifest unavailable"], jq.blocked_dependencies
  end

  def test_ignores_casks_and_unsafe_formulae
    cask = Candidate.new(item: Item.new("firefox"), type: :cask, safe: true)
    too_new = formula("jq", installed: "1.7", target: nil, latest: "1.8", safe: false)

    plan(requirements: {}, failures: { "firefox" => "unexpected", "jq" => "unexpected" }).apply([cask, too_new])

    assert cask.safe
    assert_nil cask.blocked_dependencies
    assert_nil too_new.blocked_dependencies
  end

  private

  def formula(name, installed:, target:, latest: target, safe: true)
    Candidate.new(
      item: Item.new(name),
      type: :formula,
      installed_version: installed,
      target_version: target,
      latest_version: latest,
      safe: safe,
      date_unknown: false,
      no_cutoff: false,
    )
  end

  def requirement(name, minimum, installed: nil)
    Requirement.new(name: name, minimum_version: minimum, installed_version: installed)
  end

  def plan(requirements:, older_targets: {}, failures: {})
    remaining = older_targets.transform_values(&:dup)
    Safe::DependencyPlan.new(
      requirements_for: lambda { |candidate|
        name = candidate.item.full_name
        raise failures[name] if failures.key?(name)

        requirements.fetch([name, candidate.target_version], [])
      },
      next_target: ->(candidate) { remaining.fetch(candidate.item.full_name, []).shift },
      version_satisfies: ->(target, minimum) { Gem::Version.new(target.tr("_", ".")) >= Gem::Version.new(minimum.tr("_", ".")) },
    )
  end
end
