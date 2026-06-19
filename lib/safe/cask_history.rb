# frozen_string_literal: true

require "rbconfig"
require "uri"

require_relative "date_filter"
require_relative "github_api"

module Safe
  class CaskHistory
    COMMITS_PER_PAGE = 100
    MAX_PAGES = 10

    VersionRef = Struct.new(
      :version,
      :commit_sha,
      :path,
      :publication_date,
      :content,
      keyword_init: true,
    )

    Resolution = Struct.new(:latest_ref, :target_ref, keyword_init: true)

    def initialize(fetch_commits_page: nil, fetch_cask_content: nil, arm: nil)
      @fetch_commits_page = fetch_commits_page || method(:fetch_commits_page)
      @fetch_cask_content = fetch_cask_content || method(:fetch_cask_content)
      @arm = arm.nil? ? host_arm? : arm
      @rate_limited = false
    end

    def resolve(cask:, installed_versions:, latest_version:, cutoff:)
      return Resolution.new unless supported_cask?(cask)

      latest_ref = nil
      target_ref = nil

      each_version_group(cask) do |ref|
        latest_ref ||= ref if ref.version == latest_version
        break :stop if cutoff.nil? && latest_ref
        break :stop if installed_versions.include?(ref.version)

        if cutoff && Safe::DateFilter.safe?(ref.publication_date, cutoff)
          target_ref = ref
          break :stop
        end
      end

      Resolution.new(latest_ref: latest_ref, target_ref: target_ref)
    end

    def rate_limited?
      @rate_limited
    end

    private

    def supported_cask?(cask)
      tap = cask.tap
      repo = tap&.remote_repository.to_s
      source_path = cask.respond_to?(:ruby_source_path) ? cask.ruby_source_path.to_s : ""
      !repo.empty? && !source_path.empty?
    end

    def each_version_group(cask)
      repo = cask.tap.remote_repository.to_s
      path = cask.ruby_source_path.to_s
      current_ref = nil

      each_verified_commit(repo: repo, path: path) do |commit|
        sha = commit["sha"] || commit[:sha]
        date = commit.dig("commit", "committer", "date") || commit.dig(:commit, :committer, :date)
        next if sha.nil? || date.nil?

        content = @fetch_cask_content.call(repo: repo, commit_sha: sha, path: path)
        next if content.nil? || content.empty?

        version = extract_version(content)
        next if version.nil? || version.empty? || version == "latest"

        ref = VersionRef.new(
          version: version,
          commit_sha: sha,
          path: path,
          publication_date: date,
          content: content,
        )

        if current_ref.nil?
          current_ref = ref
        elsif ref.version == current_ref.version
          current_ref = ref
        else
          result = yield current_ref
          return if result == :stop

          current_ref = ref
        end
      end

      yield current_ref if current_ref
    end

    def each_verified_commit(repo:, path:)
      (1..MAX_PAGES).each do |page|
        commits = @fetch_commits_page.call(repo: repo, path: path, page: page)
        break if commits.nil? || commits.empty?

        commits.each do |commit|
          yield commit if verified_commit?(commit)
        end
        break if commits.length < COMMITS_PER_PAGE
      end
    end

    def verified_commit?(commit)
      verification = commit.dig("commit", "verification") || commit.dig(:commit, :verification) || {}
      verified = verification["verified"] || verification[:verified]
      reason = verification["reason"] || verification[:reason]

      verified == true && reason == "valid"
    end

    def extract_version(content)
      arch_block = @arm ? "on_arm" : "on_intel"
      version_from_block(content, arch_block) || version_from_top_level(content) || version_from_line(content)
    end

    def version_from_block(content, block_name)
      block = content.match(/^\s*#{Regexp.escape(block_name)}\s+do\s*\n(?<body>.*?)^\s*end\s*$/m)&.[](:body)
      return nil unless block

      version_from_line(block)
    end

    def version_from_top_level(content)
      without_arch_blocks = content.gsub(/^\s*on_(?:arm|intel)\s+do\s*\n.*?^\s*end\s*$/m, "")
      version_from_line(without_arch_blocks)
    end

    def version_from_line(content)
      if (match = content.match(/^\s*version\s+"([^"]+)"\s*$/))
        match[1]
      elsif content.match?(/^\s*version\s+:latest\s*$/)
        "latest"
      end
    end

    def fetch_commits_page(repo:, path:, page:)
      encoded_path = URI.encode_www_form_component(path)
      url = "https://api.github.com/repos/#{repo}/commits?path=#{encoded_path}&per_page=#{COMMITS_PER_PAGE}&page=#{page}"
      response = Safe::GitHubApi.fetch_array(url)
      @rate_limited = true if response.rate_limited

      response.data
    end

    def fetch_cask_content(repo:, commit_sha:, path:)
      require "utils/curl"

      url = "https://raw.githubusercontent.com/#{repo}/#{commit_sha}/#{path}"
      result = Utils::Curl.curl_output(url)
      unless result.success?
        @rate_limited = true if result.stderr&.include?("403") || result.stdout&.include?("rate limit")
        return nil
      end

      result.stdout
    end

    def host_arm?
      RbConfig::CONFIG.fetch("host_cpu", "").match?(/arm|aarch64/i)
    end
  end
end
