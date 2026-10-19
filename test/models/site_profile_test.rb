require "test_helper"

class SiteProfileTest < ActiveSupport::TestCase
  # Build an anonymous subclass with given config for author, call methods on the class.
  def rule_with_author(**config)
    Class.new(SiteProfile) { author(**config) }
  end

  def doc(html) = Nokogiri::HTML(html)

  test "extracts text via css selector" do
    rule = rule_with_author(css: "span.author")
    result = rule.extract_author(doc('<span class="author">Jane Doe</span>'), nil)
    assert_equal "Jane Doe", result
  end

  test "extracts attribute value via attr key" do
    rule = rule_with_author(css: "meta.byline", attr: "content")
    result = rule.extract_author(doc('<meta class="byline" content="Jane Doe">'), nil)
    assert_equal "Jane Doe", result
  end

  test "falls back to fallback_css when primary selector misses" do
    rule = rule_with_author(css: "span.missing", fallback_css: "span.author")
    result = rule.extract_author(doc('<span class="author">Jane Doe</span>'), nil)
    assert_equal "Jane Doe", result
  end

  test "returns static value without touching the DOM" do
    rule = rule_with_author(static: "Static Author")
    result = rule.extract_author(doc("<html></html>"), nil)
    assert_equal "Static Author", result
  end

  test "applies regex with capture group" do
    rule = rule_with_author(css: "span.byline", regex: /By (.+)/, capture: 1)
    result = rule.extract_author(doc('<span class="byline">By Jane Doe</span>'), nil)
    assert_equal "Jane Doe", result
  end

  test "returns nil when regex does not match" do
    rule = rule_with_author(css: "span.byline", regex: /By (.+)/, capture: 1)
    result = rule.extract_author(doc('<span class="byline">Written by nobody</span>'), nil)
    assert_nil result
  end

  test "applies iso8601 transform and returns a Date" do
    rule = Class.new(SiteProfile) do
      date(css: "meta.published", attr: "content", transform: :iso8601)
    end
    result = rule.extract_date(doc('<meta class="published" content="2024-05-10">'), nil)
    assert_equal Date.new(2024, 5, 10), result
  end

  test "returns nil for iso8601 transform on invalid date string" do
    rule = Class.new(SiteProfile) { date(css: "span.date", transform: :iso8601) }
    result = rule.extract_date(doc('<span class="date">not-a-date</span>'), nil)
    assert_nil result
  end

  test "applies strip transform" do
    rule = rule_with_author(css: "span.author", transform: :strip)
    result = rule.extract_author(doc('<span class="author">  Jane  </span>'), nil)
    assert_equal "Jane", result
  end

  test "applies Proc transform" do
    rule = rule_with_author(css: "span.author", transform: ->(v) { v.upcase })
    result = rule.extract_author(doc('<span class="author">jane</span>'), nil)
    assert_equal "JANE", result
  end

  test "returns nil when css selector finds nothing" do
    rule = rule_with_author(css: "span.missing")
    result = rule.extract_author(doc("<html><body></body></html>"), nil)
    assert_nil result
  end

  test "returns nil when no config is set for the field" do
    assert_nil SiteProfile.extract_author(doc("<html></html>"), nil)
  end

  test "allowed_external_link? returns false when no domains configured" do
    assert_equal false, SiteProfile.allowed_external_link?("https://example.com/file.js")
  end

  test "allowed_external_link? returns true for exact domain match" do
    rule = Class.new(SiteProfile) { allowed_external_domains %w[cdn.com] }
    assert rule.allowed_external_link?("https://cdn.com/file.js")
  end

  test "allowed_external_link? returns true for subdomain match" do
    rule = Class.new(SiteProfile) { allowed_external_domains %w[cdn.com] }
    assert rule.allowed_external_link?("https://assets.cdn.com/file.js")
  end

  test "allowed_external_link? returns false for unrelated domain" do
    rule = Class.new(SiteProfile) { allowed_external_domains %w[cdn.com] }
    assert_equal false, rule.allowed_external_link?("https://other.com/file.js")
  end

  test "allowed_external_domains raises ArgumentError for non-array" do
    assert_raises(ArgumentError) do
      Class.new(SiteProfile) { allowed_external_domains "cdn.com" }
    end
  end
end

class SiteProfileRegistryTest < ActiveSupport::TestCase
  test "returns the profile for an exact domain" do
    assert_equal SiteProfile::PaulGraham, SiteProfile.for("paulgraham.com")
  end

  test "strips www prefix before lookup" do
    assert_equal SiteProfile::PaulGraham, SiteProfile.for("www.paulgraham.com")
  end

  test "normalizes domain to lowercase" do
    assert_equal SiteProfile::PaulGraham, SiteProfile.for("PAULGRAHAM.COM")
  end

  test "returns nil for unknown domain" do
    assert_nil SiteProfile.for("example.com")
  end

  test "returns nil for empty string" do
    assert_nil SiteProfile.for("")
  end

  test "known_archive_for returns URL for registered domain" do
    url = SiteProfile.for("shaggydev.com")&.archive_url

    assert_equal "https://shaggydev.com/all/", url
  end

  test "known_archive_for returns URL for registered domain with www prefix" do
    url = SiteProfile.for("www.shaggydev.com")&.archive_url

    assert_equal "https://shaggydev.com/all/", url
  end

  test "known_archive_for returns nil for unregistered domain" do
    url = SiteProfile.for("https://example.com/blog")&.archive_url

    assert_nil url
  end

  test "known_archive_for returns nil for blank URL" do
    assert_nil SiteProfile.for("")&.archive_url
    assert_nil SiteProfile.for(nil)&.archive_url
  end

  # Custom detector tests
  test "detector_for returns detector class for registered domain" do
    detector = SiteProfile.for("simonwillison.net")&.detector

    assert_equal ArchivePageDetector::SimonWillisonDetector, detector
  end

  test "detector_for returns detector class for registered domain with www prefix" do
    detector = SiteProfile.for("www.simonwillison.net")&.detector

    assert_equal ArchivePageDetector::SimonWillisonDetector, detector
  end

  test "detector_for returns nil for unregistered domain" do
    detector = SiteProfile.for("https://example.com/blog")&.detector

    assert_nil detector
  end

  test "detector_for returns nil for blank URL" do
    assert_nil SiteProfile.for("")&.detector
    assert_nil SiteProfile.for(nil)&.detector
  end

  test "detector_for returns nil for invalid URL" do
    assert_nil SiteProfile.for("not a url")&.detector
  end
end
