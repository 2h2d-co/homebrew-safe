# frozen_string_literal: true

require "minitest/autorun"
require "safe/date_filter"

class DateFilterTest < Minitest::Test
  # --- parse_cutoff: relative durations (time-based) ---

  def test_parse_cutoff_days
    cutoff = Safe::DateFilter.parse_cutoff("7d")
    expected = Time.now - (7 * 86_400)
    assert_in_delta expected.to_f, cutoff.to_f, 1.0
  end

  def test_parse_cutoff_zero_days
    cutoff = Safe::DateFilter.parse_cutoff("0d")
    assert_in_delta Time.now.to_f, cutoff.to_f, 1.0
  end

  def test_parse_cutoff_months_preserves_time
    ref = Time.new(2026, 4, 6, 14, 30, 0)
    cutoff = Safe::DateFilter.parse_cutoff("6m", now: ref)
    # 6 months before 2026-04-06 14:30:00 → 2025-10-06 14:30:00
    assert_equal 2025, cutoff.year
    assert_equal 10, cutoff.month
    assert_equal 6, cutoff.day
    assert_equal 14, cutoff.hour
    assert_equal 30, cutoff.min
  end

  def test_parse_cutoff_years_preserves_time
    ref = Time.new(2026, 4, 6, 10, 0, 0)
    cutoff = Safe::DateFilter.parse_cutoff("1y", now: ref)
    assert_equal 2025, cutoff.year
    assert_equal 4, cutoff.month
    assert_equal 6, cutoff.day
    assert_equal 10, cutoff.hour
  end

  def test_parse_cutoff_uppercase
    cutoff = Safe::DateFilter.parse_cutoff("30D")
    expected = Time.now - (30 * 86_400)
    assert_in_delta expected.to_f, cutoff.to_f, 1.0
  end

  def test_parse_cutoff_large_days
    cutoff = Safe::DateFilter.parse_cutoff("365d")
    expected = Time.now - (365 * 86_400)
    assert_in_delta expected.to_f, cutoff.to_f, 1.0
  end

  # --- parse_cutoff: absolute dates (pessimistic) ---

  def test_parse_cutoff_iso_date_is_midnight
    cutoff = Safe::DateFilter.parse_cutoff("2026-01-01")
    assert_equal 2026, cutoff.year
    assert_equal 1, cutoff.month
    assert_equal 1, cutoff.day
    assert_equal 0, cutoff.hour
    assert_equal 0, cutoff.min
  end

  def test_parse_cutoff_iso_date_pessimistic
    # Cutoff is midnight start of that date in local time.
    # Anything released on or after that moment is NOT safe.
    cutoff = Safe::DateFilter.parse_cutoff("2026-01-01")
    refute Safe::DateFilter.safe?("2026-01-01T10:00:00Z", cutoff)
    # Something clearly before that date should be safe
    assert Safe::DateFilter.safe?("2025-12-30T00:00:00Z", cutoff)
  end

  def test_parse_cutoff_iso_datetime
    cutoff = Safe::DateFilter.parse_cutoff("2026-01-01T00:00:00Z")
    assert_equal 2026, cutoff.year
    assert_equal 1, cutoff.month
    assert_equal 1, cutoff.day
  end

  def test_parse_cutoff_invalid_returns_nil
    assert_nil Safe::DateFilter.parse_cutoff("garbage")
  end

  def test_parse_cutoff_empty_returns_nil
    assert_nil Safe::DateFilter.parse_cutoff("")
  end

  # --- parse_cutoff: month boundary edge cases ---

  def test_parse_cutoff_months_from_jan_31
    ref = Time.new(2026, 1, 31, 12, 0, 0)
    cutoff = Safe::DateFilter.parse_cutoff("1m", now: ref)
    assert_equal 12, cutoff.month
    assert_equal 2025, cutoff.year
    assert_equal 31, cutoff.day
    assert_equal 12, cutoff.hour
  end

  def test_parse_cutoff_months_from_mar_31
    ref = Time.new(2026, 3, 31, 8, 0, 0)
    cutoff = Safe::DateFilter.parse_cutoff("1m", now: ref)
    assert_equal 2, cutoff.month
    assert_equal 2026, cutoff.year
    assert_equal 28, cutoff.day
  end

  def test_parse_cutoff_leap_year
    ref = Time.new(2024, 2, 29, 15, 30, 0)
    cutoff = Safe::DateFilter.parse_cutoff("1y", now: ref)
    assert_equal 2, cutoff.month
    assert_equal 2023, cutoff.year
    assert_equal 28, cutoff.day
    assert_equal 15, cutoff.hour
  end

  # --- safe? ---

  def test_safe_old_date
    cutoff = Time.new(2026, 1, 1)
    assert Safe::DateFilter.safe?("2025-06-15", cutoff)
  end

  def test_not_safe_new_date
    cutoff = Time.new(2026, 1, 1)
    refute Safe::DateFilter.safe?("2026-03-15", cutoff)
  end

  def test_safe_with_iso8601_publication_date
    cutoff = Time.new(2026, 1, 1)
    assert Safe::DateFilter.safe?("2025-07-01T14:12:33Z", cutoff)
  end

  def test_not_safe_with_iso8601_publication_date
    cutoff = Time.new(2025, 1, 1)
    refute Safe::DateFilter.safe?("2025-07-01T14:12:33Z", cutoff)
  end

  def test_safe_boundary_exact_match_is_not_safe
    cutoff = Time.parse("2025-07-01T14:12:33Z")
    refute Safe::DateFilter.safe?("2025-07-01T14:12:33Z", cutoff)
  end

  # --- age_description ---

  def test_age_description_today_when_same_date
    now = Time.parse("2026-05-14T23:59:00Z")
    assert_equal "today", Safe::DateFilter.age_description("2026-05-14T00:00:00Z", now: now)
  end

  def test_age_description_future_dates_are_today
    now = Time.parse("2026-05-14T12:00:00Z")
    assert_equal "today", Safe::DateFilter.age_description("2026-05-15T00:00:00Z", now: now)
  end

  def test_age_description_reports_zero_full_hours_when_less_than_one_hour_across_dates
    now = Time.parse("2026-05-14T00:15:00Z")
    assert_equal "0 hours ago", Safe::DateFilter.age_description("2026-05-13T23:45:00Z", now: now)
  end

  def test_age_description_reports_full_hours_under_one_day
    now = Time.parse("2026-05-14T01:45:36Z")
    assert_equal "2 hours ago", Safe::DateFilter.age_description("2026-05-13T23:00:00Z", now: now)
  end

  def test_age_description_reports_singular_hour_under_one_day
    now = Time.parse("2026-05-14T00:30:00Z")
    assert_equal "1 hour ago", Safe::DateFilter.age_description("2026-05-13T23:15:00Z", now: now)
  end

  def test_age_description_reports_days_and_full_hours
    now = Time.parse("2026-05-14T12:45:36Z")
    assert_equal "5 days 12 hours ago", Safe::DateFilter.age_description("2026-05-09T00:00:00Z", now: now)
  end

  def test_age_description_reports_singular_day_and_hour
    now = Time.parse("2026-05-14T12:15:00Z")
    assert_equal "1 day 1 hour ago", Safe::DateFilter.age_description("2026-05-13T10:45:00Z", now: now)
  end

  def test_age_description_omits_zero_hour_component_for_day_durations
    now = Time.parse("2026-05-14T12:59:00Z")
    assert_equal "2 days ago", Safe::DateFilter.age_description("2026-05-12T12:00:00Z", now: now)
  end

  def test_age_description_reports_elapsed_days_and_hours_for_mise_case
    now = Time.parse("2026-05-31T10:16:10+02:00")
    assert_equal "2 days 10 hours ago", Safe::DateFilter.age_description("2026-05-28T21:50:32Z", now: now)
  end

  # --- malformed input resilience ---

  def test_safe_with_malformed_date_returns_false
    cutoff = Time.new(2026, 1, 1)
    refute Safe::DateFilter.safe?("not-a-date", cutoff)
  end

  def test_age_description_with_malformed_date_returns_nil
    assert_nil Safe::DateFilter.age_description("not-a-date")
  end

  # --- age_description with injected now ---

  def test_age_description_with_now_parameter
    now = Time.parse("2026-04-07T12:00:00Z")
    date = "2026-03-28T12:00:00Z"
    result = Safe::DateFilter.age_description(date, now: now)
    assert_equal "10 days ago", result
  end
end
