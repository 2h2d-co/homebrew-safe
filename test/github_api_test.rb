# frozen_string_literal: true

require "minitest/autorun"
require "safe/github_api"

class GitHubApiTest < Minitest::Test
  CurlResult = Struct.new(:stdout)

  def test_retries_without_auth_when_authenticated_request_has_bad_credentials
    calls = []
    curl = lambda do |url, *args, secrets:|
      calls << { url: url, args: args, secrets: secrets }
      if calls.length == 1
        CurlResult.new(<<~JSON)
          {"message":"Bad credentials","status":"401"}
          401
        JSON
      else
        CurlResult.new(<<~JSON)
          [{"sha":"abc123"}]
          200
        JSON
      end
    end

    response = Safe::GitHubApi.fetch_array("https://api.github.com/example", token: "bad-token", curl_output: curl)

    assert_equal [{ "sha" => "abc123" }], response.data
    refute response.rate_limited
    assert_equal 2, calls.length
    assert calls[0][:args].include?("Authorization: token bad-token")
    refute calls[1][:args].any? { |arg| arg.start_with?("Authorization:") }
    assert_equal ["bad-token"], calls[0][:secrets]
    assert_empty calls[1][:secrets]
  end

  def test_marks_rate_limited_response
    curl = lambda do |_url, *_args, secrets:|
      assert_empty secrets
      CurlResult.new(<<~JSON)
        {"message":"API rate limit exceeded for 1.2.3.4.","status":"403"}
        403
      JSON
    end

    response = Safe::GitHubApi.fetch_array("https://api.github.com/example", token: nil, curl_output: curl)

    assert_empty response.data
    assert response.rate_limited
  end

  def test_returns_array_response
    curl = lambda do |_url, *_args, secrets:|
      assert_equal ["token"], secrets
      CurlResult.new(<<~JSON)
        [{"sha":"def456"}]
        200
      JSON
    end

    response = Safe::GitHubApi.fetch_array("https://api.github.com/example", token: "token", curl_output: curl)

    assert_equal [{ "sha" => "def456" }], response.data
    refute response.rate_limited
  end
end
