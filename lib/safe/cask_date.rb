# frozen_string_literal: true

require "json"
require "uri"
require "utils/curl"

module Safe
  module CaskDate
    # Returns ISO date string (last commit date for a cask's source file) or nil.
    # Uses GitHub API commits?path= to find the last commit touching the cask file.
    def self.last_updated(cask)
      return nil if rate_limited?

      tap = cask.tap
      return nil unless tap

      source_path = cask.ruby_source_path&.to_s
      return nil unless source_path

      repo = "#{tap.user}/#{tap.repository}"
      token = ENV["HOMEBREW_GITHUB_API_TOKEN"] || ENV["GITHUB_TOKEN"]
      auth_header = token ? ["--header", "Authorization: Bearer #{token}"] : []

      fetch_last_commit_date(repo, source_path, auth_header)
    end

    def self.fetch_last_commit_date(owner_repo, path, auth_header)
      encoded_path = URI.encode_www_form_component(path)
      url = "https://api.github.com/repos/#{owner_repo}/commits?path=#{encoded_path}&per_page=1"
      result = Utils::Curl.curl_output(
        url,
        "--header", "Accept: application/vnd.github+json",
        *auth_header,
      )

      unless result.success?
        # Only treat HTTP 403 as rate limiting; other errors are transient
        if result.stderr&.include?("403") || result.stdout&.include?("rate limit")
          @rate_limited = true
        end
        return nil
      end

      data = JSON.parse(result.stdout)
      if data.is_a?(Hash) && data["message"]&.include?("rate limit")
        @rate_limited = true
        return nil
      end
      return nil unless data.is_a?(Array) && data.first

      data.first.dig("commit", "committer", "date")
    rescue JSON::ParserError
      nil
    end

    def self.rate_limited?
      @rate_limited || false
    end

    def self.reset_rate_limit!
      @rate_limited = false
    end

    private_class_method :fetch_last_commit_date
  end
end
