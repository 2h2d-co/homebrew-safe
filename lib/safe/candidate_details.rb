# frozen_string_literal: true

require_relative "date_filter"

module Safe
  # Formats a candidate's versions and release dates for verbose output.
  module CandidateDetails
    module_function

    # "node 1.0 -> 1.2 (released 2026-01-10, 30 days ago; latest: 1.3 released 2026-02-01, 8 days ago)"
    # The latest part appears only when an older version than the latest is the target.
    def upgrade(candidate, label: candidate.item.full_name, now: nil)
      target_version = candidate.target_version || candidate.latest_version
      details = release(candidate.target_publication_date || candidate.publication_date, now:)
      if candidate.target_version && candidate.latest_version && candidate.target_version != candidate.latest_version
        details += "; latest: #{candidate.latest_version} #{release(candidate.publication_date, now:)}"
      end

      "#{label} #{candidate.installed_version} -> #{target_version} (#{details})"
    end

    def release(date, now: nil)
      return "release date unknown" if date.nil?

      "released #{date.split("T").first}, #{Safe::DateFilter.age_description(date, now:)}"
    end
  end
end
