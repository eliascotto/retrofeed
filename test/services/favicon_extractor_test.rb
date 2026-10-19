require "test_helper"

class FaviconExtractorTest < ActiveSupport::TestCase
  test "extracts favicon from link rel=icon" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="icon" href="/favicon.ico">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    assert_equal "https://example.com/favicon.ico", favicon_url
  end

  test "extracts favicon from link rel=shortcut icon" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="shortcut icon" href="/images/favicon.png">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    assert_equal "https://example.com/images/favicon.png", favicon_url
  end

  test "extracts favicon from apple-touch-icon" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="apple-touch-icon" href="/apple-icon.png">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    assert_equal "https://example.com/apple-icon.png", favicon_url
  end

  test "prefers link rel=icon over apple-touch-icon" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="apple-touch-icon" href="/apple-icon.png">
          <link rel="icon" href="/favicon.ico">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    assert_equal "https://example.com/favicon.ico", favicon_url
  end

  test "resolves absolute URLs correctly" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="icon" href="https://cdn.example.com/favicon.ico">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    assert_equal "https://cdn.example.com/favicon.ico", favicon_url
  end

  test "resolves protocol-relative URLs" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="icon" href="//cdn.example.com/favicon.ico">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    assert_equal "https://cdn.example.com/favicon.ico", favicon_url
  end

  test "falls back to default /favicon.ico when no link found" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>No favicon link</title>
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    assert_equal "https://example.com/favicon.ico", favicon_url
  end

  test "skips data URIs" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="icon" href="data:image/png;base64,iVBORw0KGgo=">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    # Should fall back to default favicon.ico since data URI is skipped
    assert_equal "https://example.com/favicon.ico", favicon_url
  end

  test "accepts Nokogiri document as input" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="icon" href="/favicon.ico">
        </head>
        <body></body>
      </html>
    HTML

    doc = Nokogiri::HTML(html)
    favicon_url = FaviconExtractor.extract_favicon_url(doc, "https://example.com")

    assert_equal "https://example.com/favicon.ico", favicon_url
  end

  test "handles case insensitive rel attribute" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="ICON" href="/favicon.ico">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    assert_equal "https://example.com/favicon.ico", favicon_url
  end

  test "handles empty href gracefully" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <link rel="icon" href="">
        </head>
        <body></body>
      </html>
    HTML

    favicon_url = FaviconExtractor.extract_favicon_url(html, "https://example.com")

    # Should fall back to default favicon.ico
    assert_equal "https://example.com/favicon.ico", favicon_url
  end
end
