# frozen_string_literal: true

require "time"
require "date"

module Safe
  module DateFilter
    RELATIVE_DURATION_RE = /\A(\d+)([dmyDMY])\z/
    ISO_DATE_RE = /\A\d{4}-\d{2}-\d{2}\z/

    # Parse a before value into a Time cutoff.
    # Supports: "7d", "30d", "6m", "1y" (relative), "2026-01-01" (ISO date), "2026-01-01T00:00:00Z" (ISO 8601).
    #
    # Relative durations use Time.now as reference for precise time-based resolution.
    # Bare dates (yyyy-mm-dd) are evaluated pessimistically: the cutoff is set to
    # midnight at the START of that date (local time), so anything released on that
    # date or later is considered too new.
    def self.parse_cutoff(before_value, now: nil)
      match = before_value.match(RELATIVE_DURATION_RE)
      if match
        amount = match[1].to_i
        unit = match[2].downcase
        ref_time = now || Time.now
        case unit
        when "d"
          ref_time - (amount * 86_400)
        when "m"
          ref_date = ref_time.to_date << amount
          Time.new(ref_date.year, ref_date.month, ref_date.day, ref_time.hour, ref_time.min, ref_time.sec)
        when "y"
          ref_date = ref_time.to_date << (amount * 12)
          Time.new(ref_date.year, ref_date.month, ref_date.day, ref_time.hour, ref_time.min, ref_time.sec)
        end
      elsif before_value.match?(ISO_DATE_RE)
        # Bare date: pessimistic — cutoff at midnight start of that date (local time)
        # Anything released on this date or later is too new
        Time.parse(before_value)
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
    rescue ArgumentError
      false
    end

    # Human-readable age description: "280 days ago", "3 months ago", "1 year ago"
    def self.age_description(date_string, now: nil)
      pub_time = Time.parse(date_string)
      seconds = (now || Time.now) - pub_time
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
    rescue ArgumentError
      nil
    end
  end
end
