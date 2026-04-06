# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "safe/config"

class ConfigTest < Minitest::Test
  def write_config(yaml_string)
    file = Tempfile.new(["brew-safe-config", ".yaml"])
    file.write(yaml_string)
    file.close
    file
  end

  # --- YAML parsing ---

  def test_loads_valid_config
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
      cask:
        firefox:
          before: "14d"
    YAML
    config = Safe::Config.new(file.path)
    assert_equal "30d", config.global_before
  ensure
    file&.unlink
  end

  def test_missing_config_file
    config = Safe::Config.new("/nonexistent/path/config.yaml")
    assert_nil config.global_before
    assert_equal({}, config.data)
  end

  def test_empty_config_file
    file = write_config("")
    config = Safe::Config.new(file.path)
    assert_nil config.global_before
    assert_equal({}, config.data)
  ensure
    file&.unlink
  end

  # --- global_before ---

  def test_global_before
    file = write_config("before: '90d'")
    config = Safe::Config.new(file.path)
    assert_equal "90d", config.global_before
  ensure
    file&.unlink
  end

  def test_global_before_missing
    file = write_config("formula:\n  node:\n    before: '7d'")
    config = Safe::Config.new(file.path)
    assert_nil config.global_before
  ensure
    file&.unlink
  end

  # --- before_for ---

  def test_before_for_formula
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
        "python@3.13":
          before: "90d"
    YAML
    config = Safe::Config.new(file.path)
    assert_equal "7d", config.before_for(:formula, "node")
    assert_equal "90d", config.before_for(:formula, "python@3.13")
  ensure
    file&.unlink
  end

  def test_before_for_cask
    file = write_config(<<~YAML)
      before: "30d"
      cask:
        firefox:
          before: "14d"
    YAML
    config = Safe::Config.new(file.path)
    assert_equal "14d", config.before_for(:cask, "firefox")
  ensure
    file&.unlink
  end

  def test_before_for_full_name_with_tap
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        "user/tap/custom-formula":
          before: "60d"
    YAML
    config = Safe::Config.new(file.path)
    assert_equal "60d", config.before_for(:formula, "user/tap/custom-formula")
  ensure
    file&.unlink
  end

  def test_before_for_missing_item
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
    YAML
    config = Safe::Config.new(file.path)
    assert_nil config.before_for(:formula, "curl")
    assert_nil config.before_for(:cask, "firefox")
  ensure
    file&.unlink
  end

  def test_before_for_missing_section
    file = write_config("before: '30d'")
    config = Safe::Config.new(file.path)
    assert_nil config.before_for(:formula, "node")
    assert_nil config.before_for(:cask, "firefox")
  ensure
    file&.unlink
  end

  # --- resolve_before ---

  def test_resolve_before_cli_takes_precedence
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
    YAML
    config = Safe::Config.new(file.path)
    result = config.resolve_before(type: :formula, full_name: "node", cli_before: "1d")
    assert_equal "1d", result
  ensure
    file&.unlink
  end

  def test_resolve_before_per_item_over_global
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
    YAML
    config = Safe::Config.new(file.path)
    result = config.resolve_before(type: :formula, full_name: "node")
    assert_equal "7d", result
  ensure
    file&.unlink
  end

  def test_resolve_before_falls_back_to_global
    file = write_config(<<~YAML)
      before: "30d"
      formula:
        node:
          before: "7d"
    YAML
    config = Safe::Config.new(file.path)
    result = config.resolve_before(type: :formula, full_name: "curl")
    assert_equal "30d", result
  ensure
    file&.unlink
  end

  def test_resolve_before_returns_nil_when_nothing_configured
    config = Safe::Config.new("/nonexistent/config.yaml")
    result = config.resolve_before(type: :formula, full_name: "curl")
    assert_nil result
  end

  # --- has_any_per_item_before? ---

  def test_has_any_per_item_before_with_formula
    file = write_config(<<~YAML)
      formula:
        node:
          before: "7d"
    YAML
    config = Safe::Config.new(file.path)
    assert config.has_any_per_item_before?
  ensure
    file&.unlink
  end

  def test_has_any_per_item_before_with_cask
    file = write_config(<<~YAML)
      cask:
        firefox:
          before: "14d"
    YAML
    config = Safe::Config.new(file.path)
    assert config.has_any_per_item_before?
  ensure
    file&.unlink
  end

  def test_has_any_per_item_before_without_overrides
    file = write_config("before: '30d'")
    config = Safe::Config.new(file.path)
    refute config.has_any_per_item_before?
  ensure
    file&.unlink
  end

  def test_has_any_per_item_before_empty_config
    config = Safe::Config.new("/nonexistent/config.yaml")
    refute config.has_any_per_item_before?
  end

  # --- validation ---

  def test_non_hash_root_raises_config_error
    file = write_config("- item1\n- item2")
    assert_raises(Safe::Config::ConfigError) do
      Safe::Config.new(file.path)
    end
  ensure
    file&.unlink
  end

  def test_invalid_yaml_syntax_raises_config_error
    file = write_config("before: [invalid yaml")
    assert_raises(Safe::Config::ConfigError) do
      Safe::Config.new(file.path)
    end
  ensure
    file&.unlink
  end

  def test_before_for_returns_string
    file = write_config(<<~YAML)
      before: 30
      formula:
        node:
          before: 7
    YAML
    config = Safe::Config.new(file.path)
    assert_equal "30", config.global_before
    assert_equal "7", config.before_for(:formula, "node")
  ensure
    file&.unlink
  end
end
