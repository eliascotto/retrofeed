require "test_helper"

# Regression coverage for the XSS sanitization layer that wraps `Markdown.to_html`
# before article bodies hit the page. Article content is sourced from arbitrary
# external blogs, so the sanitizer is the only thing standing between attacker-
# controlled HTML and the user's session.
class MarkdownHelperTest < ActionView::TestCase
  include MarkdownHelper

  # --- Script execution vectors must be stripped ---
  # The exploit surface is CommonMarker's `unsafe: true` mode: raw HTML blocks
  # (separated by blank lines) are passed through verbatim. The sanitizer must
  # remove anything that can execute. We assert the executable construct is
  # gone — plain-text occurrences of the word "alert" are harmless.

  test "strips block-level <script> tags from markdown" do
    rendered = render_markdown("hello\n\n<script>alert(1)</script>\n\nworld")
    assert_not_includes rendered, "<script"
  end

  test "strips inline event handlers from raw HTML blocks" do
    rendered = render_markdown("para\n\n<img src=x onerror=alert(1)>\n")
    assert_not_includes rendered, "onerror"
  end

  test "strips javascript: URLs from links" do
    rendered = render_markdown("[click](javascript:alert(1))")
    assert_not_includes rendered, "javascript:"
  end

  test "strips <iframe> tags" do
    rendered = render_markdown("para\n\n<iframe src=https://evil.example/></iframe>\n")
    assert_not_includes rendered, "<iframe"
  end

  test "strips <svg> with embedded scripts" do
    rendered = render_markdown("para\n\n<svg><script>alert(1)</script></svg>\n")
    assert_not_includes rendered, "<script"
  end

  test "strips <object> and <embed> tags" do
    rendered = render_markdown(%(<object data="x"></object><embed src="x">))
    assert_not_includes rendered, "<object"
    assert_not_includes rendered, "<embed"
  end

  test "strips <style> tags" do
    rendered = render_markdown(%(<style>body{display:none}</style>real text))
    assert_not_includes rendered, "<style"
    assert_includes rendered, "real text"
  end

  test "strips inline style attributes" do
    rendered = render_markdown(%(<p style="position:fixed;top:0">overlay</p>))
    assert_not_includes rendered, "style="
    assert_includes rendered, "overlay"
  end

  test "strips <form> and form controls" do
    rendered = render_markdown(%(<form action="/x"><input name="pw"></form>))
    assert_not_includes rendered, "<form"
    assert_not_includes rendered, "<input"
  end

  # --- Legitimate formatting must survive ---

  test "preserves paragraphs, emphasis, and links" do
    rendered = render_markdown("Hello **world** with a [link](https://example.com)")
    assert_includes rendered, "<strong>world</strong>"
    assert_includes rendered, %(<a href="https://example.com">link</a>)
  end

  test "preserves syntax-highlighted code blocks" do
    rendered = render_markdown("```ruby\ndef hi\nend\n```")
    assert_includes rendered, %(class="language-ruby")
    assert_includes rendered, "<span"
  end

  test "preserves tables" do
    md = "| a | b |\n| - | - |\n| 1 | 2 |\n"
    rendered = render_markdown(md)
    assert_includes rendered, "<table>"
    assert_includes rendered, "<th>a</th>"
    assert_includes rendered, "<td>1</td>"
  end

  test "preserves images with http/https sources" do
    rendered = render_markdown("![alt](https://example.com/i.png)")
    assert_includes rendered, %(<img src="https://example.com/i.png")
    assert_includes rendered, %(alt="alt")
  end

  # --- sanitize_article_html (used by the content_html branch) ---

  test "sanitize_article_html strips scripts but keeps formatting" do
    rendered = sanitize_article_html(%(<p>ok</p><script>alert(1)</script>))
    assert_includes rendered, "<p>ok</p>"
    assert_not_includes rendered, "<script"
  end

  test "sanitize_article_html returns html_safe output" do
    assert sanitize_article_html("<p>hi</p>").html_safe?
  end
end
