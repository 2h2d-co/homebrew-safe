# frozen_string_literal: true

require "json"
require "utils/curl"

module Safe
  module GhcrClient
    GHCR_V2_URL = "https://ghcr.io/v2"

    # Returns ISO date string (publication date of the bottle) or nil.
    def self.publication_date(formula)
      bottle_spec = formula.stable&.bottle_specification
      return nil unless bottle_spec

      root_url = bottle_spec.root_url
      return nil unless root_url&.include?("ghcr.io")

      slug = formula.name.tr("@", "/").tr("+", "x")
      rebuild = bottle_spec.rebuild
      version = formula.pkg_version.to_s
      tag = rebuild.positive? ? "#{version}-#{rebuild}" : version

      # Derive org/repo from root_url: https://ghcr.io/v2/homebrew/core → org=homebrew, repo=core
      match = root_url.match(%r{ghcr\.io/v2/([\w-]+)/([\w-]+)})
      return nil unless match

      org = match[1]
      repo = match[2]

      manifest_url = "#{GHCR_V2_URL}/#{org}/#{repo}/#{slug}/manifests/#{tag}"

      result = Utils::Curl.curl_output(
        manifest_url,
        "--header", "Authorization: Bearer QQ==",
        "--header", "Accept: application/vnd.oci.image.index.v1+json",
      )
      return nil unless result.success?

      data = JSON.parse(result.stdout)
      annotations = data["annotations"]
      return nil unless annotations

      annotations["org.opencontainers.image.created"]
    rescue JSON::ParserError
      nil
    end
  end
end
