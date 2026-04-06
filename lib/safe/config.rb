# frozen_string_literal: true

require "yaml"

module Safe
  class Config
    CONFIG_PATH = File.expand_path("~/.config/brew-safe/config.yaml")

    attr_reader :data

    def initialize(path = CONFIG_PATH)
      @data = if File.exist?(path)
        loaded = YAML.safe_load(File.read(path))
        unless loaded.nil? || loaded.is_a?(Hash)
          raise ConfigError, "Config must be a YAML mapping, got #{loaded.class}"
        end
        loaded || {}
      else
        {}
      end
    rescue Psych::SyntaxError => e
      raise ConfigError, "Invalid YAML in #{path}: #{e.message}"
    end

    def global_before
      @data["before"]&.to_s
    end

    # Returns the per-item before value, or nil.
    # type: :formula or :cask
    # full_name: e.g. "node", "python@3.13", "user/tap/formula"
    def before_for(type, full_name)
      section = @data[type.to_s]
      return nil unless section.is_a?(Hash)

      item = section[full_name]
      return nil unless item.is_a?(Hash)

      item["before"]&.to_s
    end

    # Resolve effective before value with precedence:
    # cli_before > per-item config > global config
    def resolve_before(type:, full_name:, cli_before: nil)
      cli_before || before_for(type, full_name) || global_before
    end

    def has_any_per_item_before?
      %w[formula cask].any? do |type|
        section = @data[type]
        section.is_a?(Hash) && section.any? { |_, v| v.is_a?(Hash) && v["before"] }
      end
    end

    class ConfigError < StandardError; end
  end
end
