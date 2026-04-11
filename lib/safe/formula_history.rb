# frozen_string_literal: true

require "json"
require "set"
require "uri"

require_relative "date_filter"

module Safe
  class FormulaHistory
    DEFAULT_ROOT_URL = "https://ghcr.io/v2/homebrew/core"
    COMMITS_PER_PAGE = 100
    MAX_PAGES = 10

    VersionRef = Struct.new(
      :version,
      :commit_sha,
      :path,
      :rebuild,
      :root_url,
      :publication_date,
      keyword_init: true,
    )

    def initialize(fetch_commits_page: nil, fetch_formula_content: nil, publication_lookup: nil)
      @fetch_commits_page = fetch_commits_page || method(:fetch_commits_page)
      @fetch_formula_content = fetch_formula_content || method(:fetch_formula_content)
      @publication_lookup = publication_lookup || method(:lookup_publication_date)
      @publication_cache = {}
      @metadata_cache = {}
    end

    def latest_safe_intermediate(formula:, installed_versions:, latest_version:, cutoff:)
      return nil unless supported_formula?(formula)

      path = formula.ruby_source_path.to_s
      seen_versions = {}
      installed_versions = installed_versions.to_set

      each_commit(path) do |commit|
        ref = version_ref_from_commit(formula.name, path, commit, seen_versions)
        next if ref.nil?
        next if ref.version == latest_version
        break :stop if installed_versions.include?(ref.version)

        publication_date = publication_date_for(formula.name, ref)
        next unless publication_date
        next unless Safe::DateFilter.safe?(publication_date, cutoff)

        return VersionRef.new(
          version: ref.version,
          commit_sha: ref.commit_sha,
          path: ref.path,
          rebuild: ref.rebuild,
          root_url: ref.root_url,
          publication_date: publication_date,
        )
      end

      nil
    end

    def formula_content_at(commit_sha:, path:)
      @fetch_formula_content.call(commit_sha: commit_sha, path: path)
    end

    private

    def supported_formula?(formula)
      tap_name = formula.tap&.name
      source_path = formula.respond_to?(:ruby_source_path) ? formula.ruby_source_path.to_s : ""
      tap_name == "homebrew/core" && !source_path.empty?
    end

    def each_commit(path)
      (1..MAX_PAGES).each do |page|
        commits = @fetch_commits_page.call(path: path, page: page)
        break if commits.nil? || commits.empty?

        commits.each do |commit|
          result = yield commit
          return if result == :stop
        end
        break if commits.length < COMMITS_PER_PAGE
      end
    end

    def version_ref_from_commit(formula_name, path, commit, seen_versions)
      sha = commit["sha"] || commit[:sha]
      message = commit.dig("commit", "message") || commit.dig(:commit, :message) || commit["message"] || commit[:message]
      version = extract_version(formula_name, message)
      return nil if version.nil? || seen_versions[version]

      seen_versions[version] = true

      VersionRef.new(
        version: version,
        commit_sha: sha,
        path: path,
        rebuild: 0,
        root_url: DEFAULT_ROOT_URL,
      )
    end

    def publication_date_for(name, ref)
      cached = @publication_cache[[name, ref.version, ref.rebuild, ref.root_url]]
      return cached if cached

      publication_date = @publication_lookup.call(
        name: name,
        version: ref.version,
        rebuild: ref.rebuild,
        root_url: ref.root_url,
      )
      return @publication_cache[[name, ref.version, ref.rebuild, ref.root_url]] = publication_date if publication_date

      metadata = metadata_for(ref)
      return nil if metadata.nil?
      return nil if metadata[:rebuild] == ref.rebuild && metadata[:root_url] == ref.root_url

      publication_date = @publication_lookup.call(
        name: name,
        version: ref.version,
        rebuild: metadata[:rebuild],
        root_url: metadata[:root_url],
      )
      return nil unless publication_date

      ref.rebuild = metadata[:rebuild]
      ref.root_url = metadata[:root_url]
      @publication_cache[[name, ref.version, ref.rebuild, ref.root_url]] = publication_date
    end

    def metadata_for(ref)
      @metadata_cache[[ref.commit_sha, ref.path]] ||= begin
        content = ref.commit_sha ? @fetch_formula_content.call(commit_sha: ref.commit_sha, path: ref.path) : nil
        extract_bottle_metadata(content)
      end
    end

    def extract_version(formula_name, message)
      return nil if message.nil? || message.empty?

      if (match = message.match(/\A#{Regexp.escape(formula_name)} (?<version>\S+)/))
        match[:version]
      elsif (match = message.match(/\A#{Regexp.escape(formula_name)}: update (?<version>\S+) bottle\./))
        match[:version]
      end
    end

    def extract_bottle_metadata(content)
      return { rebuild: 0, root_url: DEFAULT_ROOT_URL } if content.nil? || content.empty?

      body = if (match = content.match(/^\s*bottle do\n(?<body>.*?)^\s*end\n/m))
        match[:body]
      else
        ""
      end

      rebuild = if (match = body.match(/^\s*rebuild\s+(\d+)\s*$/))
        match[1].to_i
      else
        0
      end

      root_url = if (match = body.match(/^\s*root_url\s+"([^"]+)"\s*$/))
        match[1]
      else
        DEFAULT_ROOT_URL
      end

      { rebuild: rebuild, root_url: root_url }
    end

    def fetch_commits_page(path:, page:)
      require "utils/curl"
      require "utils/github/api"

      encoded_path = URI.encode_www_form_component(path)
      url = "https://api.github.com/repos/Homebrew/homebrew-core/commits?path=#{encoded_path}&per_page=#{COMMITS_PER_PAGE}&page=#{page}"
      result = Utils::Curl.curl_output(
        url,
        "--header", "Accept: application/vnd.github+json",
        *github_auth_header,
        secrets: [github_token].compact,
      )
      return [] unless result.success?

      data = JSON.parse(result.stdout)
      return [] unless data.is_a?(Array)

      data
    rescue JSON::ParserError
      []
    end

    def fetch_formula_content(commit_sha:, path:)
      require "utils/curl"

      url = "https://raw.githubusercontent.com/Homebrew/homebrew-core/#{commit_sha}/#{path}"
      result = Utils::Curl.curl_output(url)
      return nil unless result.success?

      result.stdout
    end

    def github_auth_header
      token = github_token
      return [] if token.nil? || token.empty?

      ["--header", "Authorization: token #{token}"]
    end

    def github_token
      require "utils/github/api"

      GitHub::API.credentials
    end

    def lookup_publication_date(name:, version:, rebuild:, root_url:)
      require_relative "ghcr_client"

      Safe::GhcrClient.publication_date_for(name: name, version: version, rebuild: rebuild, root_url: root_url)
    end
  end
end
