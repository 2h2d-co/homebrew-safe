# frozen_string_literal: true

require "minitest/autorun"
require "time"
require "safe/candidate_details"

class CandidateDetailsTest < Minitest::Test
  Candidate = Struct.new(
    :item, :installed_version, :target_version, :latest_version, :target_publication_date, :publication_date,
    :required_by,
    keyword_init: true,
  )
  Item = Struct.new(:full_name)

  NOW = Time.parse("2026-02-09T12:00:00Z")

  def test_latest_target_shows_its_release_date_and_age
    candidate = Candidate.new(
      item: Item.new("node"), installed_version: "1.0", target_version: "1.3", latest_version: "1.3",
      publication_date: "2026-02-01T12:00:00Z"
    )

    assert_equal "node 1.0 -> 1.3 (released 2026-02-01, 8 days ago)",
                 Safe::CandidateDetails.upgrade(candidate, now: NOW)
  end

  def test_older_target_also_shows_the_latest_version
    candidate = Candidate.new(
      item: Item.new("node"), installed_version: "1.0", target_version: "1.2", latest_version: "1.3",
      target_publication_date: "2026-01-10T12:00:00Z", publication_date: "2026-02-01T12:00:00Z"
    )

    assert_equal "node [before: 7d] 1.0 -> 1.2 (released 2026-01-10, 30 days ago; " \
                 "latest: 1.3 released 2026-02-01, 8 days ago)",
                 Safe::CandidateDetails.upgrade(candidate, label: "node [before: 7d]", now: NOW)
  end

  def test_candidate_without_target_shows_the_latest_version
    candidate = Candidate.new(
      item: Item.new("ngrok"), installed_version: "3.1", latest_version: "3.2",
      publication_date: "2026-02-09T02:00:00Z"
    )

    assert_equal "ngrok 3.1 -> 3.2 (released 2026-02-09, today)",
                 Safe::CandidateDetails.upgrade(candidate, now: NOW)
  end

  def test_added_dependency_install_shows_that_it_is_not_installed_and_what_requires_it
    candidate = Candidate.new(
      item: Item.new("curl"), target_version: "8.23.0", latest_version: "8.23.0",
      publication_date: "2026-02-01T12:00:00Z", required_by: %w[git libpq]
    )

    assert_equal "curl not installed -> 8.23.0 (released 2026-02-01, 8 days ago; required by git, libpq)",
                 Safe::CandidateDetails.upgrade(candidate, now: NOW)
  end

  def test_missing_date_is_reported_as_unknown
    candidate = Candidate.new(item: Item.new("tool"), installed_version: "1", latest_version: "2")

    assert_equal "tool 1 -> 2 (release date unknown)", Safe::CandidateDetails.upgrade(candidate, now: NOW)
  end
end
