# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "pathname"
require "safe/cask_upgrader"

class CaskUpgraderTest < Minitest::Test
  Candidate = Struct.new(:item, :upgrade_source_path, :upgrade_source_content, keyword_init: true)
  Item = Struct.new(:full_name)

  class FakeRunner
    attr_reader :calls, :observed_cask_content

    def initialize
      @calls = []
    end

    def safe_system(*args)
      @calls << args
      cask_path = Pathname(args.last)
      @observed_cask_content = cask_path.read
    end
  end

  def test_upgrade_writes_cask_to_temporary_tap_and_cleans_up
    Dir.mktmpdir do |dir|
      stale = Pathname(dir)/"2h2d-co/homebrew-safe-temp-stale"
      stale.mkpath
      (stale/Safe::CaskUpgrader::LOCK_FILENAME).write("")

      runner = FakeRunner.new
      candidate = Candidate.new(
        item: Item.new("ngrok"),
        upgrade_source_path: "Casks/n/ngrok.rb",
        upgrade_source_content: "cask \"ngrok\" do\nend\n",
      )

      Safe::CaskUpgrader.new(
        runner: runner,
        brew_file: "/opt/homebrew/bin/brew",
        tap_directory: Pathname(dir),
      ).upgrade!(candidate)

      assert_equal "cask \"ngrok\" do\nend\n", runner.observed_cask_content
      assert_equal 1, runner.calls.length
      env, brew_file, command, cask_flag, cask_path = runner.calls.first
      assert_equal "/opt/homebrew/bin/brew", brew_file
      assert_equal "upgrade", command
      assert_equal "--cask", cask_flag
      assert_equal "1", env.fetch("HOMEBREW_NO_AUTO_UPDATE")
      assert_equal "1", env.fetch("HOMEBREW_NO_REQUIRE_TAP_TRUST")
      assert_match %r{/2h2d-co/homebrew-safe-temp-[^/]+/Casks/n/ngrok\.rb\z}, cask_path
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

      Safe::CaskUpgrader.cleanup_stale_temp_taps!(tap_directory: Pathname(dir))

      refute_path_exists stale_locked
      assert_path_exists active_locked
      refute_path_exists incomplete
      assert_path_exists unrelated
    ensure
      active_lock&.close
    end
  end
end
