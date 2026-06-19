# frozen_string_literal: true

require "json"

module Safe
  module GitHubApi
    Response = Struct.new(:data, :rate_limited, :auth_failed, keyword_init: true)

    DEFAULT_TOKEN = Object.new.freeze
    private_constant :DEFAULT_TOKEN

    module_function

    def fetch_array(url, token: DEFAULT_TOKEN, curl_output: nil)
      curl_output ||= method(:curl_output)
      token = github_token if token.equal?(DEFAULT_TOKEN)

      response = fetch_array_once(url, token: token, curl_output: curl_output)
      if token && !token.empty? && response.auth_failed
        response = fetch_array_once(url, token: nil, curl_output: curl_output)
      end

      response
    end

    def fetch_array_once(url, token:, curl_output:)
      args = [
        "--header", "Accept: application/vnd.github+json",
        "--header", "X-GitHub-Api-Version: 2022-11-28",
        "--write-out", "\n%{http_code}",
      ]
      secrets = []
      if token && !token.empty?
        args += ["--header", "Authorization: token #{token}"]
        secrets << token
      end

      result = curl_output.call(url, *args, secrets: secrets)
      body, status = split_body_and_status(result.stdout.to_s)
      data = JSON.parse(body)

      if status.start_with?("2") && data.is_a?(Array)
        return Response.new(data: data, rate_limited: false, auth_failed: false)
      end

      Response.new(
        data: [],
        rate_limited: rate_limited_response?(data, status),
        auth_failed: auth_failed_response?(data, status),
      )
    rescue JSON::ParserError
      Response.new(data: [], rate_limited: false, auth_failed: false)
    end

    def split_body_and_status(stdout)
      body, separator, status = stdout.chomp.rpartition("\n")
      return [body, status] if !separator.empty? && status.match?(/\A\d{3}\z/)

      [stdout, ""]
    end

    def auth_failed_response?(data, status)
      return true if status == "401"
      return false unless data.is_a?(Hash)

      message = data["message"].to_s.downcase
      data["status"].to_s == "401" ||
        message.include?("bad credentials") ||
        message.include?("requires authentication") ||
        message.include?("must authenticate") ||
        message.include?("resource not accessible by personal access token")
    end

    def rate_limited_response?(data, status)
      return false unless data.is_a?(Hash)

      message = data["message"].to_s.downcase
      status_code = data["status"].to_s
      (status == "403" || status == "429" || status_code == "403" || status_code == "429") &&
        message.include?("rate limit")
    end

    def curl_output(*args, **kwargs)
      require "utils/curl"

      Utils::Curl.curl_output(*args, **kwargs)
    end

    def github_token
      require "utils/github/api"

      GitHub::API.credentials
    end
  end
end
