# frozen_string_literal: true

require "minitest/autorun"
require "time"
require "safe/cask_history"

class CaskHistoryTest < Minitest::Test
  FakeTap = Struct.new(:remote_repository)
  FakeCask = Struct.new(:tap, :ruby_source_path)

  def test_selects_latest_safe_intermediate_version_by_version_introduction_date
    commits = [
      commit("sha-4", "2026-05-26T22:48:11Z"),
      commit("sha-3-edit", "2026-05-21T17:21:02Z"),
      commit("sha-3", "2026-05-15T16:55:56Z"),
      commit("sha-2", "2026-04-28T17:06:25Z"),
      commit("sha-1", "2026-04-01T12:00:00Z"),
    ]
    contents = {
      "sha-4" => cask_content("4.0"),
      "sha-3-edit" => cask_content("3.0"),
      "sha-3" => cask_content("3.0"),
      "sha-2" => cask_content("2.0"),
      "sha-1" => cask_content("1.0"),
    }

    resolution = history(commits, contents).resolve(
      cask: fake_cask,
      installed_versions: ["1.0"],
      latest_version: "4.0",
      cutoff: Time.parse("2026-05-18T00:00:00Z"),
    )

    assert_equal "4.0", resolution.latest_ref.version
    assert_equal "2026-05-26T22:48:11Z", resolution.latest_ref.publication_date
    assert_equal "3.0", resolution.target_ref.version
    assert_equal "sha-3", resolution.target_ref.commit_sha
    assert_equal "2026-05-15T16:55:56Z", resolution.target_ref.publication_date
  end

  def test_skips_unverified_commits
    commits = [
      commit("sha-3", "2026-05-15T16:55:56Z", verified: false),
      commit("sha-2", "2026-04-28T17:06:25Z"),
      commit("sha-1", "2026-04-01T12:00:00Z"),
    ]
    contents = {
      "sha-3" => cask_content("3.0"),
      "sha-2" => cask_content("2.0"),
      "sha-1" => cask_content("1.0"),
    }

    resolution = history(commits, contents).resolve(
      cask: fake_cask,
      installed_versions: ["1.0"],
      latest_version: "3.0",
      cutoff: Time.parse("2026-05-18T00:00:00Z"),
    )

    assert_nil resolution.latest_ref
    assert_equal "2.0", resolution.target_ref.version
  end

  def test_stops_before_installed_version
    commits = [
      commit("sha-4", "2026-05-26T22:48:11Z"),
      commit("sha-3", "2026-05-15T16:55:56Z"),
      commit("sha-2", "2026-04-28T17:06:25Z"),
    ]
    contents = {
      "sha-4" => cask_content("4.0"),
      "sha-3" => cask_content("3.0"),
      "sha-2" => cask_content("2.0"),
    }

    resolution = history(commits, contents).resolve(
      cask: fake_cask,
      installed_versions: ["3.0"],
      latest_version: "4.0",
      cutoff: Time.parse("2026-05-18T00:00:00Z"),
    )

    assert_equal "4.0", resolution.latest_ref.version
    assert_nil resolution.target_ref
  end

  def test_uses_current_architecture_block
    commits = [commit("sha-1", "2026-05-15T16:55:56Z")]
    contents = {
      "sha-1" => <<~RUBY,
        cask "ngrok" do
          on_arm do
            version "3.39.2,c2kYG4NCXNy,a"
            sha256 "arm-sha"
          end
          on_intel do
            version "3.39.2,6mp4z58YGV3,a"
            sha256 "intel-sha"
          end
        end
      RUBY
    }

    resolution = history(commits, contents, arm: false).resolve(
      cask: fake_cask,
      installed_versions: ["3.39.1,intel,a"],
      latest_version: "3.39.2,6mp4z58YGV3,a",
      cutoff: Time.parse("2026-05-18T00:00:00Z"),
    )

    assert_equal "3.39.2,6mp4z58YGV3,a", resolution.target_ref.version
  end

  private

  def fake_cask
    FakeCask.new(FakeTap.new("Homebrew/homebrew-cask"), "Casks/n/ngrok.rb")
  end

  def history(commits, contents, arm: true)
    Safe::CaskHistory.new(
      fetch_commits_page: lambda { |repo:, path:, page:|
        assert_equal "Homebrew/homebrew-cask", repo
        assert_equal "Casks/n/ngrok.rb", path
        page == 1 ? commits : []
      },
      fetch_cask_content: lambda { |repo:, commit_sha:, path:|
        assert_equal "Homebrew/homebrew-cask", repo
        assert_equal "Casks/n/ngrok.rb", path
        contents[commit_sha]
      },
      arm: arm,
    )
  end

  def commit(sha, date, verified: true, reason: "valid")
    {
      "sha" => sha,
      "commit" => {
        "committer" => { "date" => date },
        "verification" => { "verified" => verified, "reason" => reason },
      },
    }
  end

  def cask_content(version)
    <<~RUBY
      cask "ngrok" do
        version "#{version}"
        sha256 "abc123"
      end
    RUBY
  end
end
