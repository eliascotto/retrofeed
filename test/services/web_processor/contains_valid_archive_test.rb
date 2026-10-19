require "test_helper"

class WebProcessor::ContainsValidArchiveTest < ActiveSupport::TestCase
  BASE = "https://example.com"

  # Builds a Nokogiri doc from a list of hrefs.
  def doc_with_links(*hrefs)
    body = hrefs.map { |h| %(<a href="#{h}">link</a>) }.join
    Nokogiri::HTML("<html><body>#{body}</body></html>")
  end

  def doc(html) = Nokogiri::HTML(html)

  def archive?(html_or_doc, base: BASE, **opts)
    document = html_or_doc.is_a?(Nokogiri::XML::Node) ? html_or_doc : doc(html_or_doc)
    WebProcessor.contains_valid_archive?(document, base, **opts)
  end

  # Generates count distinct hrefs from a template containing "%d".
  def slugs(template, count, from: 1)
    (from...(from + count)).map { |n| template % n }
  end

  # ---------------------------------------------------------------------------
  # Group A: not an archive (expect false)
  # ---------------------------------------------------------------------------

  test "returns false when the page has no links" do
    assert_not archive?("<html><body><p>no links here</p></body></html>")
  end

  test "returns false when every link points to another domain" do
    external = slugs("https://other.com/post-%d", 6)
    assert_not archive?(doc_with_links(*external))
  end

  test "returns false when the only local links resolve to the base path or root" do
    assert_not archive?(doc_with_links("/", "https://example.com/", "#top"))
  end

  test "returns false when every local path is filtered by the _next/icon/avi prefixes" do
    filtered = [ "/_next/static/a", "/_next/data/b", "/icon-192.png", "/icons/c", "/avi/d", "/avatar/e" ]
    assert_not archive?(doc_with_links(*filtered))
  end

  test "returns false for pages with only non-navigable hrefs" do
    assert_not archive?(doc_with_links("mailto:hi@example.com", "javascript:void(0)", "tel:+123", "#section"))
  end

  test "returns false when there are fewer than min_links article paths" do
    assert_not archive?(doc_with_links("/post-a/", "/post-b/", "/post-c/", "/post-d/"))
  end

  test "returns false for a navigation-only page" do
    nav = [ "/about", "/contact", "/category/tech", "/tag/ruby", "/page/2" ]
    assert_not archive?(doc_with_links(*nav))
  end

  # ---------------------------------------------------------------------------
  # Group B: Check 1, flat unique article slugs (overreacted.io style)
  # ---------------------------------------------------------------------------

  test "returns true for many distinct flat article slugs" do
    posts = %w[/why-react-re-renders/ /a-complete-guide-to-useeffect/ /react-as-a-ui-runtime/
               /the-elements-of-ui-engineering/ /writing-resilient-components/ /optimized-for-change/]
    assert archive?(doc_with_links(*posts))
  end

  test "returns true at exactly min_links flat slugs" do
    assert archive?(doc_with_links(*slugs("/post-%d/", 5)))
  end

  test "returns false at exactly min_links minus one flat slugs" do
    assert_not archive?(doc_with_links(*slugs("/post-%d/", 4)))
  end

  test "honors a lowered min_links threshold" do
    assert archive?(doc_with_links(*slugs("/post-%d/", 3)), min_links: 3)
    assert_not archive?(doc_with_links(*slugs("/post-%d/", 2)), min_links: 3)
  end

  test "returns true when articles meet the threshold despite extra navigation links" do
    links = slugs("/article-%d/", 5) + [ "/about", "/contact", "/category/news" ]
    assert archive?(doc_with_links(*links))
  end

  test "returns true with mixed links" do
    posts = %w[
      /blog/feed.atom
      /archive/addressing-editor-content.html
      /archive/value-reference-semantics.html
      /archive/codemirror-6.html
      /archive/facets.html
      /archive/pcall.html]
    assert archive?(doc_with_links(*posts))
  end

  # ---------------------------------------------------------------------------
  # Group C: date-based URLs (macwright.com style)
  #
  # Dated permalinks are themselves article-like paths, so they satisfy the
  # article-like count directly. The "/archive/..." cases also pass: "/archive"
  # is not in ARTICLE_EXCLUDED_PATH_PATTERNS (only "/archives" is), so those links
  # are treated as real articles — matching how extraction treats /archive/*.html.
  # ---------------------------------------------------------------------------

  test "returns true for YYYY/MM/DD dated article URLs" do
    assert archive?(doc_with_links(*slugs("/2024/01/%02d/post-title/", 5)))
  end

  test "returns true for YYYY/MM dated article URLs" do
    assert archive?(doc_with_links(*slugs("/2024/%02d/post-title/", 5)))
  end

  test "returns true for single-digit date segments" do
    assert archive?(doc_with_links(*slugs("/2024/1/%d/post-title/", 5)))
  end

  test "returns true for day-level dated archives under /archive" do
    assert archive?(doc_with_links(*slugs("/archive/2024/01/%02d/post", 5)))
  end

  test "returns true for single-digit dated segments under /archive" do
    assert archive?(doc_with_links(*slugs("/archive/2024/1/%d/post", 5)))
  end

  test "returns true for ISO dashed dated slugs under /archive" do
    assert archive?(doc_with_links(*slugs("/archive/2024-01-%02d-post-title", 5)))
  end

  test "returns true for regional day-first dated archives under /archive" do
    assert archive?(doc_with_links(*slugs("/archive/%02d-06-2024/post", 5)))
  end

  # ---------------------------------------------------------------------------
  # Group C2: excluded prefixes are never an archive, even when dated
  #
  # The validation predicate is now ArticleExtractor.article_like_path?, the same
  # one extraction uses. Links under an excluded prefix (/category, /tag, ...) are
  # not article-like, so they cannot validate as an archive regardless of their
  # date or directory structure. This is the fix for "valid archive, zero articles".
  # ---------------------------------------------------------------------------

  test "returns false for dated links under an excluded category prefix" do
    assert_not archive?(doc_with_links(*slugs("/category/2024/%02d/post", 5)))
  end

  test "returns false for dated links under an excluded tag prefix" do
    assert_not archive?(doc_with_links(*slugs("/tag/2024/%02d/post", 5)))
  end

  # ---------------------------------------------------------------------------
  # Group D: Check 3, shared directory pattern
  # ---------------------------------------------------------------------------

  test "returns true for many links sharing a directory the nav filter rejects" do
    # Each path contains "/category/" so Check 1's article filter drops them all,
    # yet they group under "/blog/category" and reach min_links via Check 3.
    links = slugs("/blog/category/slug-%d", 5)
    assert archive?(doc_with_links(*links))
  end

  test "returns true for nested article links under a common directory" do
    assert archive?(doc_with_links(*slugs("/posts/2024/01/slug-%d", 5)))
  end

  # ---------------------------------------------------------------------------
  # Group E: link normalization and resolution corner cases
  # ---------------------------------------------------------------------------

  test "resolves bare relative hrefs against a directory base url" do
    links = slugs("post-%d.html", 5)
    assert archive?(doc_with_links(*links), base: "https://example.com/blog/")
  end

  test "treats root-relative and protocol-relative links as local" do
    links = [ "/posts/a", "/posts/b", "//example.com/posts/c", "//example.com/posts/d", "/posts/e" ]
    assert archive?(doc_with_links(*links))
  end

  test "counts query-string and fragment variants of the same path (no dedup)" do
    # extract_path strips queries and fragments, so all five collapse to "/post",
    # but the method counts by length rather than uniqueness, so this reaches
    # min_links and returns true. Pins the current (non-deduping) behavior.
    links = [ "/post?utm=a", "/post?utm=b", "/post#x", "/post#y", "/post" ]
    assert archive?(doc_with_links(*links))
  end

  test "drops links equal to a path-scoped base url and counts the rest" do
    links = [ "/blog" ] + slugs("/blog/post-%d", 5)
    assert archive?(doc_with_links(*links), base: "https://example.com/blog")
  end

  test "treats www host links as external relative to the apex base" do
    links = slugs("https://www.example.com/post-%d", 5)
    assert_not archive?(doc_with_links(*links))
  end

  # ---------------------------------------------------------------------------
  # Group F: the shared predicate matches whole segments, not substrings
  #
  # ARTICLE_EXCLUDED_PATH_PATTERNS matches an exact path or a path under that
  # prefix (e.g. /about, /about/team), so slugs that merely start with those
  # letters (/aviation, /iconography, /about-react) are real articles. The old
  # inline filter used substring/loose-prefix matching and wrongly dropped them.
  # ---------------------------------------------------------------------------

  test "accepts aviation article paths (not matched by the /avi prefix)" do
    assert archive?(doc_with_links(*slugs("/aviation-news-%d/", 5)))
  end

  test "accepts iconography article paths (not matched by the /icon prefix)" do
    assert archive?(doc_with_links(*slugs("/iconography-%d/", 5)))
  end

  test "accepts flat articles whose slug starts with about" do
    assert archive?(doc_with_links(*slugs("/about-react-hooks-%d/", 5)))
  end

  test "duplicate identical links inflate the count and yield a false positive" do
    # Pins current (non-deduping) behavior: the predicate counts links, not unique paths.
    links = Array.new(5, "/post-a")
    assert archive?(doc_with_links(*links))
  end

  # ---------------------------------------------------------------------------
  # Group G: contains_valid_archive_with_reason? verdict
  # ---------------------------------------------------------------------------

  def verdict_for(*hrefs, base: BASE, **opts)
    WebProcessor.contains_valid_archive_with_reason?(doc_with_links(*hrefs), base, **opts)
  end

  test "verdict reports counts and the passing check for a flat-slug archive" do
    verdict = verdict_for(*slugs("/post-%d/", 5), "/about", "/category/news")

    assert verdict.valid?
    assert_equal :article_like, verdict.passed_check
    assert_equal 7, verdict.local_links_count
    assert_equal 7, verdict.candidate_paths_count
    assert_equal 5, verdict.article_like_count
    assert_equal 5, verdict.min_links
  end

  test "verdict counts dated paths among the article-like links" do
    verdict = verdict_for(*slugs("/2024/01/%02d/post-title/", 5))

    assert verdict.valid?
    assert_equal 5, verdict.date_paths_count
  end

  test "verdict reports the dominant directory pattern" do
    verdict = verdict_for(*slugs("/posts/2024/01/slug-%d", 5))

    assert verdict.valid?
    assert_equal "/posts/2024/01", verdict.top_pattern
    assert_equal 5, verdict.top_pattern_count
  end

  test "verdict for a rejected page is invalid with no passing check" do
    verdict = verdict_for("/about", "/contact", "/category/tech", "/tag/ruby")

    assert_not verdict.valid?
    assert_nil verdict.passed_check
    assert_equal 0, verdict.article_like_count
  end
end
