# Configuration for WebProcessor service
#
# Duration format: "<positive-integer> <unit>" e.g. "5 days", "60 minutes", "1 hour"
# Valid units: seconds, minutes, hours, days, weeks, months, years (and singular as well)
#
# WEBSITE_ARCHIVE_INTERVAL: Full archive re-crawl to discover new articles (default: 14 days)
# WEBSITE_ARCHIVE_MIN_INTERVAL: Hard minimum between website re-crawls (default: 60 minutes, floor: 10 minutes)
#
# ARTICLE_CONTENT_INTERVAL: Re-check existing article content (default: 60 days)
# ARTICLE_CONTENT_MIN_INTERVAL: Hard minimum between article refreshes (default: 30 minutes, floor: 10 minutes)
#
# NB: *_MIN_INTERVAL is used for hard re-fresh

VALID_DURATION_UNITS = %w[seconds minutes hours days weeks months years].freeze

DEFAULT_ARCHIVE_INTERVAL = 14.days.freeze
DEFAULT_ARCHIVE_MIN_INTERVAL = 60.minutes.freeze
DEFAULT_CONTENT_INTERVAL = 60.days.freeze
DEFAULT_CONTENT_MIN_INTERVAL = 30.minutes.freeze

def parse_duration(name, value, default)
  return default if value.nil? || value.strip.empty?

  parts = value.strip.split
  unless parts.length == 2
    raise ArgumentError, "Invalid duration #{value.inspect} for #{name}. " \
      "Expected \"<positive-integer> <unit>\" e.g. \"5 days\". " \
      "Valid units: #{VALID_DURATION_UNITS.join(', ')}."
  end

  amount_str, unit = parts
  unit = "#{unit}s" unless unit.end_with?("s")

  unless amount_str.match?(/\A[1-9]\d*\z/)
    raise ArgumentError, "Invalid duration #{value.inspect} for #{name}. " \
      "Amount must be a positive integer, got #{amount_str.inspect}."
  end

  unless VALID_DURATION_UNITS.include?(unit)
    raise ArgumentError, "Invalid duration #{value.inspect} for #{name}. " \
      "Unit #{unit.inspect} is not valid. Valid units: #{VALID_DURATION_UNITS.join(', ')}."
  end

  amount_str.to_i.public_send(unit)
end

Rails.application.config.after_initialize do
  # Website archive crawl interval (discover new articles)
  archive_interval = parse_duration("WEBSITE_ARCHIVE_INTERVAL", ENV["WEBSITE_ARCHIVE_INTERVAL"], DEFAULT_ARCHIVE_INTERVAL)
  WebProcessor.instance_variable_set(:@archive_interval, archive_interval)

  # Website archive minimum interval (hard floor for manual refresh)
  archive_min_interval = parse_duration("WEBSITE_ARCHIVE_MIN_INTERVAL", ENV["WEBSITE_ARCHIVE_MIN_INTERVAL"], DEFAULT_ARCHIVE_MIN_INTERVAL)
  WebProcessor.instance_variable_set(:@archive_min_interval, archive_min_interval)

  # Article content refresh interval (re-check existing articles)
  content_interval = parse_duration("ARTICLE_CONTENT_INTERVAL", ENV["ARTICLE_CONTENT_INTERVAL"], DEFAULT_CONTENT_INTERVAL)
  WebProcessor.instance_variable_set(:@content_interval, content_interval)

  # Article content minimum interval (hard floor for manual refresh)
  content_min_interval = parse_duration("ARTICLE_CONTENT_MIN_INTERVAL", ENV["ARTICLE_CONTENT_MIN_INTERVAL"], DEFAULT_CONTENT_MIN_INTERVAL)
  WebProcessor.instance_variable_set(:@content_min_interval, content_min_interval)

  # Legacy accessors (for backward compatibility)
  WebProcessor.instance_variable_set(:@update_interval, archive_interval)
  WebProcessor.instance_variable_set(:@refresh_interval, content_min_interval)
end
