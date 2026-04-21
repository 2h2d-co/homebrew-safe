# frozen_string_literal: true

module Safe
  module AutoUpdate
    REEXEC_ENV = {
      "HOMEBREW_AUTO_UPDATE_CHECKED" => "1",
      "HOMEBREW_NO_AUTO_UPDATE" => "1",
    }.freeze
    COMMAND_VERBOSE_ENV = "HOMEBREW_SAFE_COMMAND_VERBOSE"
    UPDATE_IF_NEEDED_ENV = {
      "HOMEBREW_AUTO_UPDATE_CHECKED" => nil,
    }.freeze

    module_function

    def run_if_needed!(runner:, brew_file:, argv: ARGV, command: ENV["HOMEBREW_COMMAND"], reexec: nil)
      return if env_present?("HOMEBREW_NO_AUTO_UPDATE")
      return if env_present?("HOMEBREW_AUTO_UPDATING")

      run_update_if_needed(runner: runner, brew_file:)

      # Match Homebrew's native auto-update flow by re-execing the command after
      # the update check. This guarantees the rest of the command runs in a fresh
      # process with the updated Homebrew checkout/API state.
      reexec_env, reexec_argv = reexec_env_and_args(argv)
      reexec_env.each { |key, value| ENV[key] = value }
      return if command.nil? || command.empty?

      reexec ||= ->(*args) { Kernel.exec(*args) }
      reexec.call(reexec_env, brew_file, command, *reexec_argv)
    end

    def reexec_env_and_args(argv)
      reexec_env = REEXEC_ENV.dup
      verbose_requested = false
      reexec_argv = argv.reject do |arg|
        is_verbose_flag = arg == "--verbose" || arg == "-v"
        verbose_requested ||= is_verbose_flag
        is_verbose_flag
      end
      reexec_env[COMMAND_VERBOSE_ENV] = "1" if verbose_requested
      [reexec_env, reexec_argv]
    end
    private_class_method :reexec_env_and_args

    def run_update_if_needed(runner:, brew_file:)
      if defined?(Homebrew) && Homebrew.respond_to?(:_system)
        return if Homebrew._system(UPDATE_IF_NEEDED_ENV, brew_file, "update-if-needed")

        if defined?(ErrorDuringExecution)
          raise ErrorDuringExecution.new([UPDATE_IF_NEEDED_ENV, brew_file, "update-if-needed"], status: $CHILD_STATUS)
        end

        raise "Failed to run #{brew_file} update-if-needed"
      end

      runner.safe_system UPDATE_IF_NEEDED_ENV, brew_file, "update-if-needed"
    end
    private_class_method :run_update_if_needed

    def env_present?(key)
      value = ENV[key]
      !value.nil? && !value.empty?
    end
    private_class_method :env_present?
  end
end
