# frozen_string_literal: true

require "time"
require "date"

module Safe
  module DateFilter
    RELATIVE_DURATION_RE = /\A(\d+)([dmyDMY])\z/

    # Parse a before value into a Time cutoff.
    # Supports: "7d", "6m", "1y" (relative), "2026-01-01" (ISO date), "2026-01-01T00:00:00Z" (ISO 8601).
    def self.parse_cutoff(before_value, reference_date: nil)
      match = before_value.match(RELATIVE_DURATION_RE)
      if match
        amount = match[1].to_i
        unit = match[2].downcase
        ref = reference_date || Date.today
        case unit
        when "d"
          Time.new(ref.year, ref.month, ref.day) - (amount * 86_400)
        when "m"
          date = ref << amount
          Time.new(date.year, date.month, date.day)
        when "y"
          date = ref << (amount * 12)
          Time.new(date.year, date.month, date.day)
        end
      else
        Time.parse(before_value)
      end
    rescue ArgumentError
      nil
    end

    # Is the publication date before (i.e. older than) the cutoff?
    def self.safe?(publication_date_string, cutoff_time)
      pub_time = Time.parse(publication_date_string)
      pub_time < cutoff_time
    end

    # Human-readable age description: "280 days ago", "3 months ago", "1 year ago"
    def self.age_description(date_string)
      pub_time = Time.parse(date_string)
      seconds = Time.now - pub_time
      days = (seconds / 86_400).to_i

      if days < 1
        "today"
      elsif days == 1
        "1 day ago"
      elsif days < 60
        "#{days} days ago"
      elsif days < 365
        months = (days / 30.0).round
        months = 1 if months < 1
        months == 1 ? "1 month ago" : "#{months} months ago"
      else
        years = (days / 365.0).round
        years = 1 if years < 1
        years == 1 ? "1 year ago" : "#{years} years ago"
      end
    end
  end
end
