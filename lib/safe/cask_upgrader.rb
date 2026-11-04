# frozen_string_literal: true

require "fileutils"
require "pathname"
require "prism"
require "securerandom"

module Safe
  class CaskUpgrader
    class UpgradeVerificationError < RuntimeError; end
    class UnsupportedCaskSourceError < RuntimeError; end

    # Homebrew allows these cask DSL calls only in official taps. They affect Homebrew's
    # own maintenance, not installation, so they are removed from the temporary tap copy.
    OFFICIAL_TAP_ONLY_CALLS = [:no_autobump!].freeze

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

    def initialize(runner:, brew_file:, tap_directory: nil, installed_versions: nil, verbose: false)
      @runner = runner
      @verbose = verbose
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
      tap_content = temporary_tap_content(candidate)

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
      cask_path.write(tap_content)

      tap_name = temp_tap_name(tap_path)
      tap_trusted = false
      upgrade_error = nil
      begin
        run_brew("trust", "--tap", tap_name, print_stdout: @verbose)
        tap_trusted = true
        run_brew("upgrade", *verbose_args, "--cask", cask_path.to_s, print_stdout: true)
        verify_target_installed!(candidate)
      rescue StandardError => e
        upgrade_error = e
        raise
      ensure
        untrust_temp_tap(tap_name, upgrade_error: upgrade_error) if tap_trusted
      end
    ensure
      tap_lock&.close
      FileUtils.rm_rf(tap_path) if tap_path
    end

    def self.remove_official_tap_only_calls(content)
      result = Prism.parse(content)
      unless result.success?
        raise UnsupportedCaskSourceError, "cannot parse cask source: #{result.errors.map(&:message).join(", ")}"
      end

      # Prism reports byte offsets, so edit a binary copy.
      bytes = content.b
      ranges = official_tap_only_calls(result.value).map do |call|
        call_start = call.location.start_offset
        call_end = call.location.end_offset
        line_start = bytes.rindex("\n", call_start)&.succ || 0
        line_end = bytes.index("\n", call_end)&.succ || bytes.bytesize
        alone_on_its_lines = bytes[line_start...call_start].strip.empty? && bytes[call_end...line_end].strip.empty?
        alone_on_its_lines ? (line_start...line_end) : (call_start...call_end)
      end

      ranges.sort_by(&:begin).reverse_each { |range| bytes[range] = "" }
      stripped = bytes.force_encoding(content.encoding)

      reparsed = Prism.parse(stripped)
      raise UnsupportedCaskSourceError, "removing official-tap-only calls broke the cask source" unless reparsed.success?

      remaining = official_tap_only_calls(reparsed.value)
      unless remaining.empty?
        raise UnsupportedCaskSourceError, "could not remove #{remaining.map(&:name).uniq.join(", ")} from cask source"
      end

      stripped
    end

    def self.official_tap_only_calls(node)
      calls = []
      queue = [node]
      until queue.empty?
        current = queue.shift
        calls << current if current.is_a?(Prism::CallNode) && OFFICIAL_TAP_ONLY_CALLS.include?(current.name)
        queue.concat(current.compact_child_nodes)
      end
      calls
    end
    private_class_method :official_tap_only_calls

    private

    def temporary_tap_content(candidate)
      self.class.remove_official_tap_only_calls(candidate.upgrade_source_content)
    rescue UnsupportedCaskSourceError => e
      raise UnsupportedCaskSourceError, "#{candidate.item.full_name}: #{e.message}"
    end

    # Homebrew names the tap at `Taps/<user>/homebrew-<repository>` as `<user>/<repository>`.
    def temp_tap_name(tap_path)
      "#{TEMP_TAP_USER}/#{tap_path.basename.to_s.delete_prefix("homebrew-")}"
    end

    # Keeps the trust store clean without hiding the upgrade error that is already being raised.
    def untrust_temp_tap(tap_name, upgrade_error:)
      run_brew("untrust", "--tap", tap_name, print_stdout: @verbose)
    rescue StandardError => e
      raise if upgrade_error.nil?

      warn "Could not untrust temporary tap #{tap_name}: #{e.message}"
    end

    def run_brew(*args, print_stdout:)
      @runner.run!(@brew_file, args: args, env: brew_env, print_stdout: print_stdout, print_stderr: true)
    end

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

    # Passes `--verbose` so Homebrew prints its verification and post-install steps.
    def verbose_args
      @verbose ? ["--verbose"] : []
    end

    def brew_env
      {
        "HOMEBREW_NO_AUTO_UPDATE" => "1",
        "HOMEBREW_NO_ASK" => "1",
        "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK" => "1",
        "HOMEBREW_NO_ENV_HINTS" => "1",
      }
    end
  end
end
