# frozen_string_literal: true

require "minitest/autorun"
require "safe/auto_update"

class AutoUpdateTest < Minitest::Test
  class FakeRunner
    attr_reader :calls

    def initialize
      @calls = []
    end

    def safe_system(*args)
      @calls << args
    end
  end

  def with_env(overrides)
    previous = {}
    overrides.each_key { |key| previous[key] = ENV[key] }
    overrides.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def test_run_if_needed_invokes_brew_update_if_needed
    runner = FakeRunner.new

    with_env(
      "HOMEBREW_NO_AUTO_UPDATE" => nil,
      "HOMEBREW_AUTO_UPDATING" => nil,
      "HOMEBREW_AUTO_UPDATE_CHECKED" => nil,
    ) do
      Safe::AutoUpdate.run_if_needed!(runner: runner, brew_file: "/opt/homebrew/bin/brew")

      assert_equal [["/opt/homebrew/bin/brew", "update-if-needed"]], runner.calls
      assert_equal "1", ENV["HOMEBREW_AUTO_UPDATE_CHECKED"]
      assert_equal "1", ENV["HOMEBREW_NO_AUTO_UPDATE"]
    end
  end

  def test_run_if_needed_is_skipped_when_auto_updates_are_disabled
    runner = FakeRunner.new

    with_env("HOMEBREW_NO_AUTO_UPDATE" => "1", "HOMEBREW_AUTO_UPDATING" => nil) do
      Safe::AutoUpdate.run_if_needed!(runner: runner, brew_file: "/opt/homebrew/bin/brew")

      assert_empty runner.calls
    end
  end

  def test_run_if_needed_is_skipped_while_auto_updating
    runner = FakeRunner.new

    with_env("HOMEBREW_NO_AUTO_UPDATE" => nil, "HOMEBREW_AUTO_UPDATING" => "1") do
      Safe::AutoUpdate.run_if_needed!(runner: runner, brew_file: "/opt/homebrew/bin/brew")

      assert_empty runner.calls
    end
  end
end
