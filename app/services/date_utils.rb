class DateUtils
  # Attempts to parse a date string into a Date object.
  #
  # Uses strict regex pre-validation before handing off to Date.strptime,
  # because Ruby's Date.parse is too lenient (e.g. Date.parse("123") succeeds)
  # and Date.strptime doesn't enforce fixed-width components or full-string
  # consumption (e.g. "04/05/2024" under "%Y/%m/%d" parses as year 4 AD).
  #
  # @param date [String] The date string to parse
  # @return [Date, nil] Parsed date or nil if parsing fails
  def self.parse_date(date)
    return nil if date.blank?
    return nil unless date.is_a?(String)

    str = date.strip

    # Each entry: [regex that must match the FULL string, strptime format]
    # Regexes enforce digit widths so "04" can't masquerade as year 4.
    patterns = [
      [ /\A\d{4}-\d{2}-\d{2}\z/,         "%Y-%m-%d",   :explicit ],
      [ /\A\d{4}\/\d{2}\/\d{2}\z/,       "%Y/%m/%d",   :explicit ],
      [ /\A\d{2}\/\d{2}\/\d{4}\z/,       "%m/%d/%Y",   :explicit ],
      [ /\A[A-Za-z]+ \d{1,2}, \d{4}\z/,  "%B %d, %Y",  :explicit ],
      [ /\A\d{1,2} [A-Za-z]+ \d{4}\z/,   "%d %B %Y",   :explicit ],
      [ /\A[A-Za-z]+ \d{1,2}\z/,         "%B %d",      :current_year ],
      [ /\A\d{1,2} [A-Za-z]+\z/,         "%d %B",      :current_year ]
    ]

    patterns.each do |regex, format|
      next unless str.match?(regex)

      # Try both full and abbreviated month names for the textual formats.
      candidates = format.include?("%B") ? [ format, format.sub("%B", "%b") ] : [ format ]

      candidates.each do |fmt|
        begin
          return Date.strptime(str, fmt)
        rescue ArgumentError
          next
        end
      end
    end

    nil
  end

  # Parses relative date strings like "2 hours ago", "40 days ago", "yesterday".
  #
  # Strictly matches the ENTIRE string (after stripping) — this is critical to
  # avoid false positives on article prose like "I wrote this 2 days ago when...".
  # Only intended to be called from contexts where a date is semantically expected
  # (e.g. <time> text, title attributes, byline elements), never on free text.
  #
  # @param date [String] The relative date string
  # @param reference [Date] The date to compute "ago" from (default: today)
  # @return [Date, nil] The computed date, or nil if the string isn't a recognized format
  def self.parse_relative_date(date, reference: Date.current)
    return nil if date.blank?
    return nil unless date.is_a?(String)

    str = date.strip.downcase
    return nil if str.empty?

    # Idiomatic relative terms
    case str
    when "just now", "now", "today"
      return reference
    when "yesterday"
      return reference - 1
    end

    # "<N> <unit>[s] ago" — full form
    if (match = str.match(/\A(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago\z/))
      return shift_date(reference, match[1].to_i, match[2])
    end

    # "<N><unit> ago" — compact form (2h ago, 3d ago, 40d ago)
    # Only accept s/m/h/d/w/mo/y — explicit unit required, no bare numbers.
    if (match = str.match(/\A(\d+)\s*(mo|[smhdwy])\s+ago\z/))
      unit = expand_compact_unit(match[2])
      return shift_date(reference, match[1].to_i, unit) if unit
    end

    # "a <unit> ago" / "an hour ago" (common in humanized output)
    if (match = str.match(/\A(?:a|an)\s+(second|minute|hour|day|week|month|year)\s+ago\z/))
      return shift_date(reference, 1, match[1])
    end

    nil
  end

  # ISO 8601 is what structured data and <time datetime> almost always use.
  # Date.iso8601 is strict (unlike Date.parse) — perfect for this path.
  def self.parse_iso8601_date(date)
    return nil if date.blank?
    return nil unless date.is_a?(String)

    # Handle both date-only ("2024-03-15") and full timestamp ("2024-03-15T10:30:00Z")
    Date.iso8601(date.to_s.strip[0, 10])
  rescue ArgumentError, Date::Error
    nil
  end

  private
    def self.shift_date(reference, amount, unit)
      # Sanity bound: refuse absurd values that are almost certainly parse errors
      # or garbage. 100 years ≈ 36500 days covers any realistic "X ago" content.
      return nil if amount > 36_500

      case unit
      when "second", "minute", "hour" then reference # sub-day → still today
      when "day"                       then reference - amount
      when "week"                      then reference - (amount * 7)
      when "month"                     then reference << amount
      when "year"                      then reference << (amount * 12)
      end
    end

    def self.expand_compact_unit(abbr)
      {
        "s"  => "second",
        "m"  => "minute", # note: ambiguous with "month"; we treat single "m" as minute
        "h"  => "hour",
        "d"  => "day",
        "w"  => "week",
        "mo" => "month",
        "y"  => "year"
      }[abbr]
    end
end
