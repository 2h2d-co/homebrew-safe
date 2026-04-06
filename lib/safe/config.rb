# frozen_string_literal: true

require "yaml"

module Safe
  class Config
    CONFIG_PATH = File.expand_path("~/.config/brew-safe/config.yaml")

    attr_reader :data

    def initialize(path = CONFIG_PATH)
      @data = if File.exist?(path)
        YAML.safe_load(File.read(path)) || {}
      else
        {}
      end
    end

    def global_before
      @data["before"]
    end

    # Returns the per-item before value, or nil.
    # type: :formula or :cask
    # full_name: e.g. "node", "python@3.13", "user/tap/formula"
    def before_for(type, full_name)
      section = @data[type.to_s]
      return nil unless section

      item = section[full_name]
      return nil unless item

      item["before"]
    end

    # Resolve effective before value with precedence:
    # cli_before > per-item config > global config
    def resolve_before(type:, full_name:, cli_before: nil)
      cli_before || before_for(type, full_name) || global_before
    end
  end
end
