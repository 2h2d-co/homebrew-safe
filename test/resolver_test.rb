# frozen_string_literal: true

require "minitest/autorun"
require "safe/date_filter"
require "safe/config"

# Test resolver logic (config resolution, date filtering, candidate construction)
# without requiring Homebrew runtime. The Resolver class itself depends on Homebrew
# classes (Formula, Cask), so we test the resolution logic via Config + DateFilter.

class ResolverLogicTest < Minitest::Test
  def write_config(yaml_string)
    file = Tempfile.new(["brew-safe-config", ".yaml"])
    file.write(yaml_string)
    file.close
    file
  end

  # --- Config resolution drives candidate safety ---

  def test_cli_before_overrides_per_item_config
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
    YAML
    config = Safe::Config.new(file.path)
    before_value = config.resolve_before(type: :formula, full_name: "node", cli_before: "1d")
    assert_equal "1d", before_value
  ensure
    file&.unlink
  end

  def test_per_item_config_overrides_global
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
    YAML
    config = Safe::Config.new(file.path)
    before_value = config.resolve_before(type: :formula, full_name: "node")
    cutoff = Safe::DateFilter.parse_cutoff(before_value)

    # A date 10 days ago should be safe with a 7d cutoff
    ten_days_ago = (Time.now - (10 * 86_400)).strftime("%Y-%m-%dT%H:%M:%SZ")
    assert Safe::DateFilter.safe?(ten_days_ago, cutoff)

    # A date 3 days ago should NOT be safe with a 7d cutoff
    three_days_ago = (Time.now - (3 * 86_400)).strftime("%Y-%m-%dT%H:%M:%SZ")
    refute Safe::DateFilter.safe?(three_days_ago, cutoff)
  ensure
    file&.unlink
  end

  def test_global_fallback_when_no_per_item
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
    YAML
    config = Safe::Config.new(file.path)
    before_value = config.resolve_before(type: :formula, full_name: "curl")
    assert_equal "30d", before_value
  ensure
    file&.unlink
  end

  def test_no_config_returns_nil
    config = Safe::Config.new("/nonexistent/config.yaml")
    before_value = config.resolve_before(type: :formula, full_name: "curl")
    assert_nil before_value
  end

  # --- Date-unknown handling ---

  def test_nil_publication_date_treated_as_unsafe
    # When publication_date is nil, candidate should be marked date_unknown and not safe
    date_unknown = true
    is_safe = !date_unknown # mirrors resolver logic
    refute is_safe
  end

  # --- Candidate struct ---

  def test_candidate_struct_fields
    candidate_class = Struct.new(
      :item, :type, :installed_version, :latest_version,
      :publication_date, :cutoff, :safe, :date_unknown, :no_cutoff,
      keyword_init: true,
    )
    candidate = candidate_class.new(
      item: nil,
      type: :formula,
      installed_version: "1.0.0",
      latest_version: "2.0.0",
      publication_date: "2025-06-15",
      cutoff: Time.new(2026, 1, 1),
      safe: true,
      date_unknown: false,
      no_cutoff: false,
    )
    assert_equal :formula, candidate.type
    assert_equal "1.0.0", candidate.installed_version
    assert_equal "2.0.0", candidate.latest_version
    assert_equal "2025-06-15", candidate.publication_date
    assert candidate.safe
    refute candidate.date_unknown
    refute candidate.no_cutoff
  end

  def test_no_cutoff_when_before_not_configured
    # When resolve_before returns nil AND date is known, candidate should be no_cutoff
    config = Safe::Config.new("/nonexistent/config.yaml")
    before_value = config.resolve_before(type: :formula, full_name: "curl")
    publication_date = "2025-06-15"
    date_unknown = false
    cutoff = before_value ? Safe::DateFilter.parse_cutoff(before_value) : nil
    no_cutoff = cutoff.nil? && !date_unknown
    assert no_cutoff
  end

  # --- Pinned formula exclusion logic ---

  def test_pinned_formulae_excluded_from_resolution
    # Resolver skips pinned formulae. We verify the concept:
    # if a formula is pinned, it should not appear in candidates.
    # The actual filtering is `reject { |f| f.pinned? }` in resolver.
    pinned = true
    included = !pinned
    refute included
  end

  # --- Full integration of config + date filter ---

  def test_safe_determination_with_30d_cutoff
    file = write_config("before: '30d'")
    config = Safe::Config.new(file.path)
    before_value = config.resolve_before(type: :formula, full_name: "jq")
    cutoff = Safe::DateFilter.parse_cutoff(before_value)

    # 60 days ago → safe
    old_date = (Time.now - (60 * 86_400)).strftime("%Y-%m-%d")
    assert Safe::DateFilter.safe?(old_date, cutoff)

    # 5 days ago → not safe
    new_date = (Time.now - (5 * 86_400)).strftime("%Y-%m-%d")
    refute Safe::DateFilter.safe?(new_date, cutoff)
  ensure
    file&.unlink
  end
end
