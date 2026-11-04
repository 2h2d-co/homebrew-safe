# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "pathname"
require "safe/cask_upgrader"

class CaskUpgraderTest < Minitest::Test
  Candidate = Struct.new(
    :item,
    :target_version,
    :latest_version,
    :upgrade_source_path,
    :upgrade_source_content,
    keyword_init: true,
  )
  Item = Struct.new(:full_name)

  class FakeRunner
    attr_reader :calls, :observed_cask_content

    def initialize(fail_on: nil)
      @calls = []
      @fail_on = fail_on
    end

    def run!(executable, args:, env:, print_stdout:, print_stderr:)
      raise "Command errors must remain visible" unless print_stderr

      command = args.first
      raise "Upgrade output must remain visible" if command == "upgrade" && !print_stdout

      @calls << [env, executable, *args]
      @observed_cask_content = Pathname(args.last).read if command == "upgrade"
      raise "#{command} failed" if command == @fail_on
    end

    def commands
      @calls.map { |_env, _executable, *args| args }
    end
  end

  NGROK_CASK = "cask \"ngrok\" do\nend\n"

  def candidate(content: NGROK_CASK)
    Candidate.new(
      item: Item.new("ngrok"),
      target_version: "3.39.10",
      latest_version: "3.39.11",
      upgrade_source_path: "Casks/n/ngrok.rb",
      upgrade_source_content: content,
    )
  end

  def upgrader(runner, dir, installed: "3.39.10", verbose: false)
    Safe::CaskUpgrader.new(
      runner: runner,
      brew_file: "/opt/homebrew/bin/brew",
      tap_directory: Pathname(dir),
      installed_versions: ->(_candidate) { [installed] },
      verbose: verbose,
    )
  end

  def test_upgrade_writes_cask_to_temporary_tap_and_cleans_up
    Dir.mktmpdir do |dir|
      stale = Pathname(dir)/"2h2d-co/homebrew-safe-temp-stale"
      stale.mkpath
      (stale/Safe::CaskUpgrader::LOCK_FILENAME).write("")

      runner = FakeRunner.new
      upgrader(runner, dir).upgrade!(candidate)

      assert_equal NGROK_CASK, runner.observed_cask_content
      assert_equal 3, runner.calls.length
      env, brew_file, *upgrade_args = runner.calls[1]
      assert_equal "/opt/homebrew/bin/brew", brew_file
      assert_equal %w[upgrade --cask], upgrade_args.first(2)
      assert_match %r{/2h2d-co/homebrew-safe-temp-[^/]+/Casks/n/ngrok\.rb\z}, upgrade_args.last
      assert_equal "1", env.fetch("HOMEBREW_NO_AUTO_UPDATE")
      assert_equal "1", env.fetch("HOMEBREW_NO_ASK")
      refute env.key?("HOMEBREW_NO_REQUIRE_TAP_TRUST")
      assert_empty Dir.glob(File.join(dir, "2h2d-co", "homebrew-safe-temp-*"))
    end
  end

  def test_upgrade_trusts_only_the_temporary_tap_while_upgrading
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new
      upgrader(runner, dir).upgrade!(candidate)

      trust, upgrade, untrust = runner.commands
      tap_directory = upgrade.last[%r{/2h2d-co/homebrew-(safe-temp-[^/]+)/}, 1]
      assert_equal ["trust", "--tap", "2h2d-co/#{tap_directory}"], trust
      assert_equal "upgrade", upgrade.first
      assert_equal ["untrust", "--tap", "2h2d-co/#{tap_directory}"], untrust
    end
  end

  def test_failed_upgrade_still_untrusts_and_removes_the_temporary_tap
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new(fail_on: "upgrade")

      error = assert_raises(RuntimeError) { upgrader(runner, dir).upgrade!(candidate) }

      assert_equal "upgrade failed", error.message
      assert_equal %w[trust upgrade untrust], runner.commands.map(&:first)
      assert_empty Dir.glob(File.join(dir, "2h2d-co", "homebrew-safe-temp-*"))
    end
  end

  def test_untrust_failure_does_not_hide_the_upgrade_failure
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new(fail_on: "upgrade")
      runner.define_singleton_method(:run!) do |executable, args:, env:, print_stdout:, print_stderr:|
        @calls << [env, executable, *args]
        raise "#{args.first} failed" if %w[upgrade untrust].include?(args.first)
      end

      error = nil
      _stdout, stderr = capture_io do
        error = assert_raises(RuntimeError) { upgrader(runner, dir).upgrade!(candidate) }
      end

      assert_equal "upgrade failed", error.message
      assert_match "Could not untrust temporary tap 2h2d-co/safe-temp-", stderr
    end
  end

  def test_untrust_failure_fails_an_otherwise_successful_upgrade
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new(fail_on: "untrust")

      error = assert_raises(RuntimeError) { upgrader(runner, dir).upgrade!(candidate) }

      assert_equal "untrust failed", error.message
      assert_empty Dir.glob(File.join(dir, "2h2d-co", "homebrew-safe-temp-*"))
    end
  end

  def test_failed_trust_skips_the_upgrade_and_the_untrust
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new(fail_on: "trust")

      assert_raises(RuntimeError) { upgrader(runner, dir).upgrade!(candidate) }

      assert_equal [%w[trust]], runner.commands.map { |args| args.first(1) }
      assert_empty Dir.glob(File.join(dir, "2h2d-co", "homebrew-safe-temp-*"))
    end
  end

  def test_upgrade_removes_no_autobump_from_the_temporary_tap_copy
    content = <<~RUBY
      cask "font-symbols-only-nerd-font" do
        version "3.5.1"
        sha256 "01172f37db8543edb102e5cb5c64101c9f4686630804d49b419aa07b23a69996"

        url "https://github.com/ryanoasis/nerd-fonts/releases/download/v\#{version}/NerdFontsSymbolsOnly.tar.xz"

        no_autobump! because: :bumped_by_upstream

        font "SymbolsNerdFont-Regular.ttf"
      end
    RUBY

    Dir.mktmpdir do |dir|
      runner = FakeRunner.new
      upgrader(runner, dir).upgrade!(candidate(content: content))

      assert_equal content.sub("  no_autobump! because: :bumped_by_upstream\n", ""), runner.observed_cask_content
    end
  end

  def test_remove_official_tap_only_calls_handles_multiline_calls_and_keeps_other_code
    content = <<~RUBY
      cask "example" do
        version "1.0" # café
        no_autobump!(
          because: "upstream publishes releases"
        )
        on_arm do
          no_autobump! because: :bumped_by_upstream
          url "https://example.com/arm.zip"
        end
        app "Example.app"
      end
    RUBY

    expected = <<~RUBY
      cask "example" do
        version "1.0" # café
        on_arm do
          url "https://example.com/arm.zip"
        end
        app "Example.app"
      end
    RUBY

    assert_equal expected, Safe::CaskUpgrader.remove_official_tap_only_calls(content)
  end

  def test_remove_official_tap_only_calls_keeps_content_without_them
    assert_equal NGROK_CASK, Safe::CaskUpgrader.remove_official_tap_only_calls(NGROK_CASK)
  end

  def test_unparseable_cask_source_is_rejected_before_any_brew_command
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new

      error = assert_raises(Safe::CaskUpgrader::UnsupportedCaskSourceError) do
        upgrader(runner, dir).upgrade!(candidate(content: "cask \"ngrok\" do\n"))
      end

      assert_match "ngrok: cannot parse cask source", error.message
      assert_empty runner.calls
      assert_empty Dir.glob(File.join(dir, "2h2d-co", "homebrew-safe-temp-*"))
    end
  end

  def test_verbose_upgrade_passes_verbose_to_homebrew
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new
      upgrader(runner, dir, verbose: true).upgrade!(candidate)

      upgrade = runner.commands.find { |args| args.first == "upgrade" }
      assert_equal ["upgrade", "--verbose", "--cask"], upgrade.first(3)
      assert_match %r{/Casks/n/ngrok\.rb\z}, upgrade.last
    end
  end

  def test_upgrade_fails_when_the_target_version_was_not_installed
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new

      error = assert_raises(Safe::CaskUpgrader::UpgradeVerificationError) do
        upgrader(runner, dir, installed: "3.39.9").upgrade!(candidate)
      end

      assert_match "expected 3.39.10", error.message
      assert_equal "untrust", runner.commands.last.first
      assert_empty Dir.glob(File.join(dir, "2h2d-co", "homebrew-safe-temp-*"))
    end
  end

  def test_cleanup_removes_only_stale_temp_taps
    Dir.mktmpdir do |dir|
      root = Pathname(dir)/"2h2d-co"
      root.mkpath

      stale_locked = root/"homebrew-safe-temp-stale-locked"
      active_locked = root/"homebrew-safe-temp-active-locked"
      incomplete = root/"homebrew-safe-temp-incomplete"
      unrelated = root/"homebrew-safe"

      paths = [stale_locked, active_locked, incomplete, unrelated]
      paths.each(&:mkpath)
      (stale_locked/Safe::CaskUpgrader::LOCK_FILENAME).write("")
      active_lock = File.open(active_locked/Safe::CaskUpgrader::LOCK_FILENAME, File::RDWR | File::CREAT, 0o600)
      active_lock.flock(File::LOCK_EX)

      runner = FakeRunner.new
      Safe::CaskUpgrader.cleanup_stale_temp_taps!(runner: runner, brew_file: "/opt/homebrew/bin/brew",
                                                  tap_directory: Pathname(dir), trusted_taps: -> { [] })

      refute_path_exists stale_locked
      assert_path_exists active_locked
      refute_path_exists incomplete
      assert_path_exists unrelated
      assert_empty runner.calls
    ensure
      active_lock&.close
    end
  end

  def test_cleanup_untrusts_temp_taps_whose_directory_is_gone_or_stale
    Dir.mktmpdir do |dir|
      root = Pathname(dir)/"2h2d-co"
      (root/"homebrew-safe-temp-crashed").mkpath
      (root/"homebrew-safe-temp-crashed"/Safe::CaskUpgrader::LOCK_FILENAME).write("")
      active = root/"homebrew-safe-temp-active"
      active.mkpath
      active_lock = File.open(active/Safe::CaskUpgrader::LOCK_FILENAME, File::RDWR | File::CREAT, 0o600)
      active_lock.flock(File::LOCK_EX)

      trusted = %w[
        2h2d-co/safe
        2h2d-co/safe-temp-active
        2h2d-co/safe-temp-crashed
        2h2d-co/safe-temp-deleted
        2h2d-co/tap
        someone/safe-temp-deleted
      ]
      runner = FakeRunner.new
      Safe::CaskUpgrader.cleanup_stale_temp_taps!(runner: runner, brew_file: "/opt/homebrew/bin/brew",
                                                  tap_directory: Pathname(dir), trusted_taps: -> { trusted })

      assert_equal [%w[untrust --tap 2h2d-co/safe-temp-crashed 2h2d-co/safe-temp-deleted]], runner.commands
      env, brew_file, = runner.calls.first
      assert_equal "/opt/homebrew/bin/brew", brew_file
      assert_equal "1", env.fetch("HOMEBREW_NO_AUTO_UPDATE")
      assert_path_exists active
    ensure
      active_lock&.close
    end
  end

  def test_cleanup_warns_instead_of_failing_when_untrust_fails
    Dir.mktmpdir do |dir|
      runner = FakeRunner.new(fail_on: "untrust")

      _stdout, stderr = capture_io do
        Safe::CaskUpgrader.cleanup_stale_temp_taps!(runner: runner, brew_file: "/opt/homebrew/bin/brew",
                                                    tap_directory: Pathname(dir),
                                                    trusted_taps: -> { ["2h2d-co/safe-temp-deleted"] })
      end

      assert_match "Could not untrust stale temporary taps 2h2d-co/safe-temp-deleted: untrust failed", stderr
    end
  end
end
