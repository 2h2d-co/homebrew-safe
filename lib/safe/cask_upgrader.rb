# frozen_string_literal: true

require "fileutils"
require "pathname"
require "securerandom"

module Safe
  class CaskUpgrader
    class UpgradeVerificationError < RuntimeError; end

    TEMP_TAP_USER = "2h2d-co"
    TEMP_TAP_PREFIX = "homebrew-safe-temp-"
    LOCK_FILENAME = ".brew-safe-temp-tap.lock"
    GLOBAL_LOCK_FILENAME = ".brew-safe-temp-taps.lock"

    def self.cleanup_stale_temp_taps!(tap_directory: nil)
      with_global_lock(tap_directory) do |tap_root|
        tap_root.children.each do |path|
          next unless path.directory?
          next unless path.basename.to_s.start_with?(TEMP_TAP_PREFIX)

          FileUtils.rm_rf(path) if stale_temp_tap?(path)
        end
      end
    end

    def self.with_global_lock(tap_directory)
      tap_root = Pathname(tap_directory || HOMEBREW_TAP_DIRECTORY)/TEMP_TAP_USER
      FileUtils.mkdir_p(tap_root)

      File.open(tap_root/GLOBAL_LOCK_FILENAME, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        yield tap_root
      end
    end
    private_class_method :with_global_lock

    def self.stale_temp_tap?(path)
      lock = path/LOCK_FILENAME
      return true unless lock.file?

      lock_available?(lock)
    end
    private_class_method :stale_temp_tap?

    def self.lock_available?(lock)
      File.open(lock, File::RDWR) do |file|
        return false unless file.flock(File::LOCK_EX | File::LOCK_NB)

        file.flock(File::LOCK_UN)
        true
      end
    rescue Errno::ENOENT
      true
    end
    private_class_method :lock_available?

    def initialize(runner:, brew_file:, tap_directory: nil, installed_versions: nil)
      @runner = runner
      @brew_file = brew_file
      @tap_directory = Pathname(tap_directory || HOMEBREW_TAP_DIRECTORY)
      @installed_versions = installed_versions || method(:default_installed_versions)
    end

    def upgrade!(candidate)
      if candidate.upgrade_source_content.to_s.empty?
        raise "missing cask source content for #{candidate.item.full_name}"
      end
      raise "missing cask source path for #{candidate.item.full_name}" if candidate.upgrade_source_path.to_s.empty?

      source_path = Pathname(candidate.upgrade_source_path.to_s)
      if source_path.absolute? || source_path.each_filename.include?("..")
        raise "unsafe cask source path for #{candidate.item.full_name}"
      end

      tap_lock = nil
      tap_path = nil
      self.class.send(:with_global_lock, @tap_directory) do |tap_root|
        tap_root.children.each do |path|
          next unless path.directory?
          next unless path.basename.to_s.start_with?(TEMP_TAP_PREFIX)

          FileUtils.rm_rf(path) if self.class.send(:stale_temp_tap?, path)
        end

        tap_path = tap_root/"#{TEMP_TAP_PREFIX}#{Process.pid}-#{SecureRandom.hex(8)}"
        FileUtils.mkdir_p(tap_path)
        tap_lock = File.open(tap_path/LOCK_FILENAME, File::RDWR | File::CREAT, 0o600)
        tap_lock.flock(File::LOCK_EX)
      end

      cask_path = tap_path/source_path
      FileUtils.mkdir_p(cask_path.dirname)
      cask_path.write(candidate.upgrade_source_content)

      @runner.safe_system brew_env, @brew_file, "upgrade", "--cask", cask_path.to_s
      verify_target_installed!(candidate)
    ensure
      tap_lock&.close
      FileUtils.rm_rf(tap_path) if tap_path
    end

    private

    def verify_target_installed!(candidate)
      target_version = (candidate.target_version || candidate.latest_version).to_s
      installed_versions = @installed_versions.call(candidate).compact.map(&:to_s)
      return if installed_versions.include?(target_version)

      installed = installed_versions.empty? ? "none" : installed_versions.join(", ")
      raise UpgradeVerificationError,
            "#{candidate.item.full_name}: expected #{target_version} after upgrade, but installed version is #{installed}"
    end

    def default_installed_versions(candidate)
      [candidate.item.installed_version]
    end

    def brew_env
      {
        "HOMEBREW_NO_AUTO_UPDATE" => "1",
        "HOMEBREW_NO_ASK" => "1",
        "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK" => "1",
        "HOMEBREW_NO_REQUIRE_TAP_TRUST" => "1",
        "HOMEBREW_NO_ENV_HINTS" => "1",
      }
    end
  end
end
