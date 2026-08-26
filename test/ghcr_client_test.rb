# frozen_string_literal: true

require "minitest/autorun"

module Utils
  module Curl
    class << self
      attr_accessor :handler

      def curl_output(*args)
        raise "curl_output must be stubbed" unless handler

        handler.call(*args)
      end
    end
  end
end
$LOADED_FEATURES << "utils/curl.rb"

require "safe/ghcr_client"

class GhcrClientTest < Minitest::Test
  CurlResult = Struct.new(:stdout) do
    def success?
      true
    end
  end

  def test_fetches_a_manifest_for_an_exact_ghcr_root
    calls = []
    curl_output = lambda do |url, *args|
      calls << [url, args]
      CurlResult.new(
        JSON.generate(
          "annotations" => { "org.opencontainers.image.created" => "2026-08-01T12:00:00Z" },
        ),
      )
    end

    publication_date = with_curl_output(curl_output) do
      Safe::GhcrClient.publication_date_for(
        name: "python@3.13",
        version: "3.13.7",
        rebuild: 1,
        root_url: "https://ghcr.io/v2/homebrew/core",
      )
    end

    assert_equal "2026-08-01T12:00:00Z", publication_date
    assert_equal 1, calls.length
    assert_equal(
      "https://ghcr.io/v2/homebrew/core/python/3.13/manifests/3.13.7-1",
      calls[0][0],
    )
  end

  def test_rejects_noncanonical_ghcr_roots_without_fetching
    invalid_roots = [
      nil,
      "",
      "http://ghcr.io/v2/homebrew/core",
      "https://ghcr.io.example.com/v2/homebrew/core",
      "https://ghcr.io@evil.example/v2/homebrew/core",
      "https://evil.example/v2/ghcr.io/homebrew/core",
      "https://ghcr.io:8443/v2/homebrew/core",
      "https://ghcr.io/v2/homebrew/core/extra",
      "https://ghcr.io/v2/homebrew/core?redirect=evil.example",
      "not a URL containing ghcr.io/v2/homebrew/core",
    ]

    invalid_roots.each do |root_url|
      with_curl_output(->(*) { flunk "must not fetch #{root_url.inspect}" }) do
        assert_nil(
          Safe::GhcrClient.publication_date_for(
            name: "mise",
            version: "2026.8.0",
            root_url: root_url,
          ),
          root_url,
        )
      end
    end
  end

  private

  def with_curl_output(handler)
    previous_handler = Utils::Curl.handler
    Utils::Curl.handler = handler
    yield
  ensure
    Utils::Curl.handler = previous_handler
  end
end
