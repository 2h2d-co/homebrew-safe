# frozen_string_literal: true

module Safe
  module AutoUpdate
    REEXEC_ENV = {
      "HOMEBREW_AUTO_UPDATE_CHECKED" => "1",
      "HOMEBREW_NO_AUTO_UPDATE" => "1",
    }.freeze

    module_function

    def run_if_needed!(runner:, brew_file:, argv: ARGV, command: ENV["HOMEBREW_COMMAND"], reexec: nil)
      return if env_present?("HOMEBREW_NO_AUTO_UPDATE")
      return if env_present?("HOMEBREW_AUTO_UPDATING")

      runner.safe_system brew_file, "update-if-needed"

      # Match Homebrew's native auto-update flow by re-execing the command after
      # the update check. This guarantees the rest of the command runs in a fresh
      # process with the updated Homebrew checkout/API state.
      REEXEC_ENV.each { |key, value| ENV[key] = value }
      return if command.nil? || command.empty?

      reexec ||= ->(*args) { Kernel.exec(*args) }
      reexec.call(REEXEC_ENV, brew_file, command, *argv)
    end

    def env_present?(key)
      value = ENV[key]
      !value.nil? && !value.empty?
    end
    private_class_method :env_present?
  end
end
