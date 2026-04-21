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

  def test_run_if_needed_invokes_brew_update_if_needed_and_reexecs_command
    runner = FakeRunner.new
    reexec_args = nil

    with_env(
      "HOMEBREW_NO_AUTO_UPDATE" => nil,
      "HOMEBREW_AUTO_UPDATING" => nil,
      "HOMEBREW_AUTO_UPDATE_CHECKED" => nil,
      "HOMEBREW_COMMAND" => "safe-outdated",
    ) do
      Safe::AutoUpdate.run_if_needed!(
        runner: runner,
        brew_file: "/opt/homebrew/bin/brew",
        argv: ["--verbose"],
        reexec: ->(*args) { reexec_args = args },
      )

      assert_equal [[{"HOMEBREW_AUTO_UPDATE_CHECKED" => nil}, "/opt/homebrew/bin/brew", "update-if-needed"]], runner.calls
      assert_equal "1", ENV["HOMEBREW_AUTO_UPDATE_CHECKED"]
      assert_equal "1", ENV["HOMEBREW_NO_AUTO_UPDATE"]
      assert_equal "1", ENV[Safe::AutoUpdate::COMMAND_VERBOSE_ENV]
      assert_equal [
        {
          "HOMEBREW_AUTO_UPDATE_CHECKED" => "1",
          "HOMEBREW_NO_AUTO_UPDATE" => "1",
          "HOMEBREW_SAFE_COMMAND_VERBOSE" => "1",
        },
        "/opt/homebrew/bin/brew",
        "safe-outdated",
      ], reexec_args
    end
  end

  def test_run_if_needed_reexecs_when_command_is_passed_explicitly
    runner = FakeRunner.new
    reexec_args = nil

    with_env(
      "HOMEBREW_NO_AUTO_UPDATE" => nil,
      "HOMEBREW_AUTO_UPDATING" => nil,
      "HOMEBREW_AUTO_UPDATE_CHECKED" => nil,
      "HOMEBREW_COMMAND" => nil,
    ) do
      Safe::AutoUpdate.run_if_needed!(
        runner: runner,
        brew_file: "/opt/homebrew/bin/brew",
        argv: ["--verbose"],
        command: "safe-outdated",
        reexec: ->(*args) { reexec_args = args },
      )

      assert_equal [[{"HOMEBREW_AUTO_UPDATE_CHECKED" => nil}, "/opt/homebrew/bin/brew", "update-if-needed"]], runner.calls
      assert_equal [
        {
          "HOMEBREW_AUTO_UPDATE_CHECKED" => "1",
          "HOMEBREW_NO_AUTO_UPDATE" => "1",
          "HOMEBREW_SAFE_COMMAND_VERBOSE" => "1",
        },
        "/opt/homebrew/bin/brew",
        "safe-outdated",
      ], reexec_args
    end
  end

  def test_run_if_needed_is_skipped_when_auto_updates_are_disabled
    runner = FakeRunner.new
    reexec_called = false

    with_env("HOMEBREW_NO_AUTO_UPDATE" => "1", "HOMEBREW_AUTO_UPDATING" => nil) do
      Safe::AutoUpdate.run_if_needed!(
        runner: runner,
        brew_file: "/opt/homebrew/bin/brew",
        reexec: ->(*) { reexec_called = true },
      )

      assert_empty runner.calls
      refute reexec_called
    end
  end

  def test_run_if_needed_is_skipped_while_auto_updating
    runner = FakeRunner.new
    reexec_called = false

    with_env("HOMEBREW_NO_AUTO_UPDATE" => nil, "HOMEBREW_AUTO_UPDATING" => "1") do
      Safe::AutoUpdate.run_if_needed!(
        runner: runner,
        brew_file: "/opt/homebrew/bin/brew",
        reexec: ->(*) { reexec_called = true },
      )

      assert_empty runner.calls
      refute reexec_called
    end
  end
end
