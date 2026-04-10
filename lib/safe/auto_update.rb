# frozen_string_literal: true

module Safe
  module AutoUpdate
    module_function

    def run_if_needed!(runner:, brew_file:)
      return if env_present?("HOMEBREW_NO_AUTO_UPDATE")
      return if env_present?("HOMEBREW_AUTO_UPDATING")

      runner.safe_system brew_file, "update-if-needed"

      # Avoid a second auto-update in any nested `brew` invocation during this run.
      ENV["HOMEBREW_AUTO_UPDATE_CHECKED"] = "1"
      ENV["HOMEBREW_NO_AUTO_UPDATE"] = "1"
    end

    def env_present?(key)
      value = ENV[key]
      !value.nil? && !value.empty?
    end
    private_class_method :env_present?
  end
end
