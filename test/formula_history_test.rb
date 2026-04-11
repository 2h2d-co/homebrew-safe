# frozen_string_literal: true

require "minitest/autorun"
require "safe/date_filter"
require "safe/formula_history"

class FormulaHistoryTest < Minitest::Test
  FakeTap = Struct.new(:name)
  FakeFormula = Struct.new(:name, :tap, :ruby_source_path)

  def test_selects_latest_safe_intermediate_version
    commits = [
      { "sha" => "sha-47-bottle", "commit" => { "message" => "mise: update 2026.4.7 bottle." } },
      { "sha" => "sha-47", "commit" => { "message" => "mise 2026.4.7" } },
      { "sha" => "sha-46-bottle", "commit" => { "message" => "mise: update 2026.4.6 bottle." } },
      { "sha" => "sha-46", "commit" => { "message" => "mise 2026.4.6" } },
      { "sha" => "sha-45-bottle", "commit" => { "message" => "mise: update 2026.4.5 bottle." } },
      { "sha" => "sha-45", "commit" => { "message" => "mise 2026.4.5" } },
    ]
    contents = {
      "sha-47-bottle" => bottle_file,
      "sha-46-bottle" => bottle_file,
      "sha-45-bottle" => bottle_file,
    }
    publication_dates = {
      "2026.4.7" => "2026-04-09T12:13:06Z",
      "2026.4.6" => "2026-04-08T03:37:18Z",
      "2026.4.5" => "2026-04-06T12:05:04Z",
    }

    history = Safe::FormulaHistory.new(
      fetch_commits_page: ->(path:, page:) do
        assert_equal "Formula/m/mise.rb", path
        assert_equal 1, page
        commits
      end,
      fetch_formula_content: ->(commit_sha:, path:) do
        assert_equal "Formula/m/mise.rb", path
        contents[commit_sha]
      end,
      publication_lookup: ->(name:, version:, rebuild:, root_url:) do
        assert_equal "mise", name
        assert_equal 0, rebuild
        assert_equal Safe::FormulaHistory::DEFAULT_ROOT_URL, root_url
        publication_dates[version]
      end,
    )

    cutoff = Safe::DateFilter.parse_cutoff("5d", now: Time.utc(2026, 4, 11, 19, 33, 16))
    formula = FakeFormula.new("mise", FakeTap.new("homebrew/core"), "Formula/m/mise.rb")

    target = history.latest_safe_intermediate(
      formula: formula,
      installed_versions: ["2026.4.4"],
      latest_version: "2026.4.7",
      cutoff: cutoff,
    )

    refute_nil target
    assert_equal "2026.4.5", target.version
    assert_equal "sha-45-bottle", target.commit_sha
    assert_equal "2026-04-06T12:05:04Z", target.publication_date
  end

  def test_returns_nil_when_only_installed_version_is_safe
    commits = [
      { "sha" => "sha-45-bottle", "commit" => { "message" => "mise: update 2026.4.5 bottle." } },
      { "sha" => "sha-44-bottle", "commit" => { "message" => "mise: update 2026.4.4 bottle." } },
    ]
    publication_dates = {
      "2026.4.5" => "2026-04-10T12:05:04Z",
      "2026.4.4" => "2026-04-01T12:05:04Z",
    }

    history = Safe::FormulaHistory.new(
      fetch_commits_page: ->(path:, page:) do
        assert_equal "Formula/m/mise.rb", path
        assert_equal 1, page
        commits
      end,
      fetch_formula_content: ->(**) { bottle_file },
      publication_lookup: ->(name:, version:, **_) do
        assert_equal "mise", name
        publication_dates[version]
      end,
    )

    cutoff = Safe::DateFilter.parse_cutoff("7d", now: Time.utc(2026, 4, 11, 19, 33, 16))
    formula = FakeFormula.new("mise", FakeTap.new("homebrew/core"), "Formula/m/mise.rb")

    target = history.latest_safe_intermediate(
      formula: formula,
      installed_versions: ["2026.4.4"],
      latest_version: "2026.4.5",
      cutoff: cutoff,
    )

    assert_nil target
  end

  def test_stops_paging_once_installed_version_is_reached
    page_one = [
      { "sha" => "sha-47", "commit" => { "message" => "mise 2026.4.7" } },
      { "sha" => "sha-46", "commit" => { "message" => "mise 2026.4.6" } },
      { "sha" => "sha-45", "commit" => { "message" => "mise 2026.4.5" } },
      { "sha" => "sha-44", "commit" => { "message" => "mise 2026.4.4" } },
    ] + Array.new(Safe::FormulaHistory::COMMITS_PER_PAGE - 4) do |i|
      { "sha" => "noise-#{i}", "commit" => { "message" => "other formula #{i}" } }
    end

    looked_up_versions = []
    history = Safe::FormulaHistory.new(
      fetch_commits_page: ->(path:, page:) do
        assert_equal "Formula/m/mise.rb", path
        return page_one if page == 1

        flunk "should not fetch page #{page} after reaching installed version"
      end,
      fetch_formula_content: ->(**) { flunk "should not fetch content" },
      publication_lookup: ->(name:, version:, **_) do
        assert_equal "mise", name
        looked_up_versions << version
        {
          "2026.4.7" => "2026-04-10T12:00:00Z",
          "2026.4.6" => "2026-04-10T11:00:00Z",
          "2026.4.5" => "2026-04-10T10:00:00Z",
        }[version]
      end,
    )

    cutoff = Safe::DateFilter.parse_cutoff("2d", now: Time.utc(2026, 4, 11, 19, 33, 16))
    formula = FakeFormula.new("mise", FakeTap.new("homebrew/core"), "Formula/m/mise.rb")

    assert_nil history.latest_safe_intermediate(
      formula: formula,
      installed_versions: ["2026.4.4"],
      latest_version: "2026.4.8",
      cutoff: cutoff,
    )
    assert_equal %w[2026.4.7 2026.4.6 2026.4.5], looked_up_versions
  end

  def test_unsupported_formula_returns_nil
    history = Safe::FormulaHistory.new(
      fetch_commits_page: ->(**) { flunk "should not fetch commits" },
      fetch_formula_content: ->(**) { flunk "should not fetch content" },
      publication_lookup: ->(**) { flunk "should not lookup publication date" },
    )

    cutoff = Safe::DateFilter.parse_cutoff("7d", now: Time.utc(2026, 4, 11, 19, 33, 16))
    formula = FakeFormula.new("mise", FakeTap.new("user/custom"), "Formula/m/mise.rb")

    assert_nil history.latest_safe_intermediate(
      formula: formula,
      installed_versions: ["2026.4.4"],
      latest_version: "2026.4.7",
      cutoff: cutoff,
    )
  end

  private

  def bottle_file
    <<~RUBY
      class Mise < Formula
        desc "dev tools"

        bottle do
          sha256 cellar: :any_skip_relocation, arm64_sequoia: "abc"
        end
      end
    RUBY
  end
end
