require "test_helper"

# Assumes `parse_date` lives on a class/module called DateParser.
# Adjust the `subject` helper below to point at wherever your method actually lives
# (e.g. SomeScraper.new.parse_date, ArticleParser.parse_date, etc.).
class DateUtilsTest < ActiveSupport::TestCase
  def subject(input)
    DateUtils.parse_date(input)
  end

  # ---------------------------------------------------------------------------
  # Nil / blank / non-string inputs
  # ---------------------------------------------------------------------------

  test "returns nil for nil input" do
    assert_nil subject(nil)
  end

  test "returns nil for empty string" do
    assert_nil subject("")
  end

  test "returns nil for whitespace-only string" do
    assert_nil subject("   ")
    assert_nil subject("\t\n")
  end

  # ---------------------------------------------------------------------------
  # The bug we actually care about: lenient Date.parse footguns
  # These inputs MUST return nil. If any of these return a Date, the method
  # has regressed to the old lenient behavior.
  # ---------------------------------------------------------------------------

  test "returns nil for bare integer-like string '123'" do
    assert_nil subject("123"), "'123' must not be parsed as a day-of-month"
  end

  test "returns nil for single digit" do
    assert_nil subject("1")
    assert_nil subject("5")
    assert_nil subject("9")
  end

  test "returns nil for two digits" do
    assert_nil subject("12")
    assert_nil subject("31")
  end

  test "returns nil for a bare year" do
    # "2024" alone is ambiguous — Date.parse would return Jan 1 2024. Reject it.
    assert_nil subject("2024")
    assert_nil subject("1999")
  end

  test "returns nil for a bare month name" do
    assert_nil subject("May")
    assert_nil subject("January")
    assert_nil subject("Feb")
  end

  test "returns nil for month + day without year" do
    assert_equal Date.new(Date.today.year, 5, 3), subject("May 3")
    assert_equal Date.new(Date.today.year, 1, 15), subject("Jan 15")
  end

  test "returns nil for random prose containing numbers" do
    assert_nil subject("Chapter 3")
    assert_nil subject("Page 42")
    assert_nil subject("Issue 7")
    assert_nil subject("Volume 12, Number 4")
  end

  test "returns nil for currency-like strings" do
    assert_nil subject("$19.99")
    assert_nil subject("€50")
  end

  test "returns nil for pure garbage" do
    assert_nil subject("hello world")
    assert_nil subject("lorem ipsum")
    assert_nil subject("not a date at all")
  end

  test "returns nil for HTML fragments" do
    assert_nil subject("<div>123</div>")
    assert_nil subject("&nbsp;")
  end

  # ---------------------------------------------------------------------------
  # Happy path: strict formats the method explicitly supports
  # ---------------------------------------------------------------------------

  test "parses ISO 8601 (YYYY-MM-DD)" do
    assert_equal Date.new(2024, 3, 15), subject("2024-03-15")
  end

  test "parses YYYY/MM/DD" do
    assert_equal Date.new(2024, 3, 15), subject("2024/03/15")
  end

  test "parses full month name, day, year" do
    assert_equal Date.new(2024, 3, 15), subject("March 15, 2024")
  end

  test "parses abbreviated month, day, year" do
    assert_equal Date.new(2024, 3, 15), subject("Mar 15, 2024")
  end

  test "parses day full-month year" do
    assert_equal Date.new(2024, 3, 15), subject("15 March 2024")
  end

  test "parses day abbreviated-month year" do
    assert_equal Date.new(2024, 3, 15), subject("15 Mar 2024")
  end

  test "parses US-style MM/DD/YYYY" do
    assert_equal Date.new(2024, 3, 15), subject("03/15/2024")
  end

  # ---------------------------------------------------------------------------
  # Edge cases inside valid formats
  # ---------------------------------------------------------------------------

  test "parses leap day correctly" do
    assert_equal Date.new(2024, 2, 29), subject("2024-02-29")
  end

  test "returns nil for invalid leap day in non-leap year" do
    assert_nil subject("2023-02-29")
  end

  test "returns nil for impossible month" do
    assert_nil subject("2024-13-01")
  end

  test "returns nil for impossible day" do
    assert_nil subject("2024-04-31") # April has 30 days
    assert_nil subject("2024-01-32")
  end

  test "parses first and last day of year" do
    assert_equal Date.new(2024, 1, 1), subject("2024-01-01")
    assert_equal Date.new(2024, 12, 31), subject("2024-12-31")
  end

  test "parses very old and far-future dates" do
    assert_equal Date.new(1900, 1, 1), subject("1900-01-01")
    assert_equal Date.new(2099, 12, 31), subject("2099-12-31")
  end

  # ---------------------------------------------------------------------------
  # Format ambiguity / format fidelity
  # ---------------------------------------------------------------------------

  test "MM/DD/YYYY is interpreted as US-style, not DD/MM/YYYY" do
    # 04/05/2024 → April 5, 2024 (per the %m/%d/%Y format in the list)
    assert_equal Date.new(2024, 4, 5), subject("04/05/2024")
  end

  test "does not accept 2-digit years in MM/DD/YYYY" do
    # "03/15/24" should not silently become 2024 or 0024 — fail closed.
    assert_nil subject("03/15/24")
  end

  # ---------------------------------------------------------------------------
  # Whitespace / casing tolerance within otherwise-valid strings
  # ---------------------------------------------------------------------------

  test "tolerates surrounding whitespace on a valid date" do
    assert_equal Date.new(2024, 3, 15), subject("  2024-03-15  ")
  end

  # ---------------------------------------------------------------------------
  # Non-string inputs — should not raise
  # ---------------------------------------------------------------------------

  test "does not raise on integer input" do
    assert_nothing_raised { subject(123) }
    assert_nil subject(123)
  end

  test "does not raise on Date input" do
    assert_nothing_raised { subject(Date.new(2024, 1, 1)) }
  end

  test "does not raise on array or hash input" do
    assert_nothing_raised { subject([]) }
    assert_nothing_raised { subject({}) }
    assert_nil subject([])
    assert_nil subject({})
  end

  # ---------------------------------------------------------------------------
  # Real-world HTML-scraped samples
  # ---------------------------------------------------------------------------

  test "parses dates commonly found in article bylines" do
    assert_equal Date.new(2024, 3, 15), subject("March 15, 2024")
    assert_equal Date.new(2024, 3, 15), subject("Mar 15, 2024")
    assert_equal Date.new(2024, 3, 15), subject("15 March 2024")
  end

  test "rejects pagination / count strings mistakenly passed in" do
    assert_nil subject("Page 1 of 10")
    assert_nil subject("1,234 views")
    assert_nil subject("5 min read")
  end

  test "iso8601 happy paths" do
    assert_equal Date.new(2024, 3, 15),
             DateUtils.parse_iso8601_date("2024-03-15"),
             "date-only string"
    assert_equal Date.new(2024, 3, 15),
                DateUtils.parse_iso8601_date("2024-03-15T10:30:00Z"),
                "full UTC timestamp → date part only"
    assert_equal Date.new(2024, 3, 15),
                DateUtils.parse_iso8601_date("2024-03-15T23:59:59+11:00"),
                "timestamp with positive offset → date part only"
    assert_equal Date.new(2024, 3, 15),
                DateUtils.parse_iso8601_date("  2024-03-15  "),
                "surrounding whitespace is stripped"
    assert_equal Date.new(2024, 3, 1),
                DateUtils.parse_iso8601_date("2024-03"),
                "year-month only (should return date part only)"
  end

  test "iso8601 malformed/recpvery" do
    assert_nil DateUtils.parse_iso8601_date("not-a-date"), "garbage string"
    assert_nil DateUtils.parse_iso8601_date("2024/03/15"),  "slash-delimited (not ISO 8601)"
    assert_nil DateUtils.parse_iso8601_date("15-03-2024"),  "DD-MM-YYYY (wrong order)"
    assert_nil DateUtils.parse_iso8601_date("2024-13-01"),  "invalid month 13"
    assert_nil DateUtils.parse_iso8601_date("2024-03-32"),  "invalid day 32"
  end

  test "iso8601 edge cases" do
    assert_equal Date.new(2024, 2, 29),
             DateUtils.parse_iso8601_date("2024-02-29"),
             "leap day on leap year"
    assert_nil DateUtils.parse_iso8601_date("2023-02-29"),   "Feb 29 on non-leap year → nil"
    assert_equal Date.new(2024, 1,  1),
             DateUtils.parse_iso8601_date("2024-01-01"),
             "New Year's Day"
  end
end
