# frozen_string_literal: true

require "minitest/autorun"
require "safe/formula_dependencies"

class FormulaDependenciesTest < Minitest::Test
  def test_minimum_version_includes_a_positive_revision
    assert_equal "1.22.2_2", Safe::FormulaDependencies.minimum_version({ "version" => "1.22.2", "revision" => 2 })
  end

  def test_minimum_version_omits_a_zero_revision
    assert_equal "4.0.3", Safe::FormulaDependencies.minimum_version({ "version" => "4.0.3", "revision" => 0 })
  end

  def test_minimum_version_is_nil_without_a_recorded_version
    assert_nil Safe::FormulaDependencies.minimum_version(nil)
    assert_nil Safe::FormulaDependencies.minimum_version({ "version" => "" })
  end
end
