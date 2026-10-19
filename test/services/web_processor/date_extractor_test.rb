require "test_helper"

class WebProcessor::DateExtractorTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Wraps HTML in a minimal document so Nokogiri gives us an element we can
  # pass to extract_date as "the container".
  def container_for(html)
    Nokogiri::HTML.fragment("<article>#{html}</article>").at_css("article")
  end

  def extract(html, url: nil, base_url: nil)
    WebProcessor::DateExtractor.extract_date(container_for(html), url, base_url)
  end

  # ---------------------------------------------------------------------------
  # Priority 1: JSON-LD structured data (highest signal)
  # ---------------------------------------------------------------------------

  test "extracts datePublished from JSON-LD" do
    html = <<~HTML
      <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"NewsArticle","datePublished":"2024-03-15T10:30:00Z"}
      </script>
      <p>Body content.</p>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts datePublished from JSON-LD with date-only string" do
    html = <<~HTML
      <script type="application/ld+json">
        {"@type":"Article","datePublished":"2024-03-15"}
      </script>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts datePublished from nested JSON-LD @graph" do
    html = <<~HTML
      <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebSite","name":"Example"},
          {"@type":"NewsArticle","datePublished":"2024-03-15T10:30:00Z"}
        ]}
      </script>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts datePublished from JSON-LD array at root" do
    html = <<~HTML
      <script type="application/ld+json">
        [{"@type":"BreadcrumbList"},{"@type":"Article","datePublished":"2024-03-15"}]
      </script>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "falls back to dateCreated if datePublished missing" do
    html = <<~HTML
      <script type="application/ld+json">
        {"@type":"Article","dateCreated":"2024-03-15T00:00:00Z"}
      </script>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "skips malformed JSON-LD and continues to next source" do
    html = <<~HTML
      <script type="application/ld+json">{ this is not valid json }</script>
      <meta property="article:published_time" content="2024-03-15T10:30:00Z">
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "skips JSON-LD without any date fields" do
    html = <<~HTML
      <script type="application/ld+json">
        {"@type":"Organization","name":"Example Corp"}
      </script>
      <meta property="article:published_time" content="2024-03-15">
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  # ---------------------------------------------------------------------------
  # Priority 1b: Meta tags
  # ---------------------------------------------------------------------------

  test "extracts article:published_time meta tag" do
    html = '<meta property="article:published_time" content="2024-03-15T10:30:00Z">'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts article:modified_time meta tag when no published_time" do
    html = '<meta property="article:modified_time" content="2024-03-15T10:30:00Z">'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "prefers article:published_time over article:modified_time" do
    html = <<~HTML
      <meta property="article:published_time" content="2024-03-15T10:30:00Z">
      <meta property="article:modified_time" content="2024-06-20T10:30:00Z">
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts itemprop datePublished meta tag" do
    html = '<meta itemprop="datePublished" content="2024-03-15">'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts name=pubdate meta tag" do
    html = '<meta name="pubdate" content="2024-03-15">'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "ignores meta tag with blank content" do
    html = <<~HTML
      <meta property="article:published_time" content="">
      <time datetime="2024-03-15T10:30:00Z">March 15</time>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  # ---------------------------------------------------------------------------
  # Priority 2: <time> element
  # ---------------------------------------------------------------------------

  test "extracts from <time datetime> with ISO timestamp" do
    html = '<time datetime="2024-03-15T10:30:00Z">March 15, 2024</time>'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts from <time datetime> with date only" do
    html = '<time datetime="2024-03-15">March 15</time>'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "prefers <time datetime> over bare <time>" do
    html = <<~HTML
      <time>2 hours ago</time>
      <time datetime="2024-03-15">elsewhere</time>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "falls back to <time> title attribute" do
    html = '<time title="March 15, 2024">2 hours ago</time>'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "falls back to <time> text content if it parses strictly" do
    html = "<time>March 15, 2024</time>"
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "ignores <time> with unparseable relative text" do
    html = <<~HTML
      <time>2 hours ago</time>
      <meta property="article:published_time" content="2024-03-15">
    HTML
    # The bare <time> should NOT poison the result; meta should win.
    # (Actually JSON-LD/meta runs first, so meta wins regardless — but this
    # confirms the bare <time> doesn't short-circuit to nil.)
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "skips <time> with invalid datetime attribute and tries next" do
    html = <<~HTML
      <time datetime="not-a-date">bad</time>
      <time datetime="2024-03-15">good</time>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  # ---------------------------------------------------------------------------
  # Priority 3: class-based selectors
  # ---------------------------------------------------------------------------

  test "extracts from element with class containing 'published'" do
    html = '<span class="article-published">2024-03-15</span>'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts from element with class containing 'post-date'" do
    html = '<div class="post-date">March 15, 2024</div>'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "prefers datetime attribute over text on class-matched element" do
    html = '<span class="date" datetime="2024-03-15">yesterday</span>'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "extracts from data-date attribute on class-matched element" do
    html = '<span class="published-date" data-date="2024-03-15">15 Mar</span>'
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "prefers specific class selectors over generic [class*=date]" do
    html = <<~HTML
      <span class="date">not the real date</span>
      <span class="article-published">2024-03-15</span>
    HTML
    # 'published' is checked before the generic 'date' selector.
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "tries multiple elements matching the same selector" do
    html = <<~HTML
      <span class="date">invalid text</span>
      <span class="date">2024-03-15</span>
    HTML
    # Should iterate past the first one when it fails to parse.
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  # ---------------------------------------------------------------------------
  # Priority 4: URL fallback
  # ---------------------------------------------------------------------------

  test "does not attempt URL extraction without both url and base_url" do
    html = "<p>No date here.</p>"
    assert_nil extract(html)
    assert_nil extract(html, url: "https://example.com/post")
    assert_nil extract(html, base_url: "https://example.com")
  end

  # ---------------------------------------------------------------------------
  # Priority ordering — the important invariants
  # ---------------------------------------------------------------------------

  test "JSON-LD wins over meta tag when both present" do
    html = <<~HTML
      <script type="application/ld+json">
        {"@type":"Article","datePublished":"2024-03-15"}
      </script>
      <meta property="article:published_time" content="2024-06-20">
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "meta tag wins over <time> element" do
    html = <<~HTML
      <meta property="article:published_time" content="2024-03-15">
      <time datetime="2024-06-20">June 20</time>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "<time datetime> wins over class selector" do
    html = <<~HTML
      <time datetime="2024-03-15">March 15</time>
      <span class="published">2024-06-20</span>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  # ---------------------------------------------------------------------------
  # Return nil for empty / dateless containers
  # ---------------------------------------------------------------------------

  test "returns nil for empty container" do
    assert_nil extract("")
  end

  test "returns nil for container with no dates anywhere" do
    html = "<p>Just some body text with no dates.</p><div>More content.</div>"
    assert_nil extract(html)
  end

  # ---------------------------------------------------------------------------
  # Real-world-ish fixtures
  # ---------------------------------------------------------------------------

  test "handles a typical news article layout" do
    html = <<~HTML
      <header>
        <h1>Breaking News Story</h1>
        <div class="byline">
          By Jane Doe
          <time datetime="2024-03-15T14:30:00-05:00" class="publish-date">
            March 15, 2024
          </time>
        </div>
      </header>
      <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"NewsArticle",
         "datePublished":"2024-03-15T14:30:00-05:00",
         "dateModified":"2024-03-16T09:00:00-05:00"}
      </script>
      <p>Article body goes here.</p>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "handles blog with only meta tags" do
    html = <<~HTML
      <meta name="pubdate" content="2024-03-15">
      <article>
        <h1>Post Title</h1>
        <p>Content.</p>
      </article>
    HTML
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "handles sidebar widgets without being fooled by them" do
    html = <<~HTML
      <aside class="sidebar">
        <div class="related-date">2020-01-01</div>
        <div class="related-date">2019-05-20</div>
      </aside>
      <article>
        <meta property="article:published_time" content="2024-03-15">
        <p>Main article content.</p>
      </article>
    HTML
    # Meta tag should win over the sidebar "date" elements
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  # ---------------------------------------------------------------------------
  # Defensive behavior
  # ---------------------------------------------------------------------------

  test "handles JSON-LD with non-string date values gracefully" do
    html = <<~HTML
      <script type="application/ld+json">
        {"@type":"Article","datePublished":12345}
      </script>
      <meta property="article:published_time" content="2024-03-15">
    HTML
    # Non-string datePublished should be ignored, falling through to meta.
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  test "handles deeply nested JSON-LD without stack issues" do
    nested = { "@type" => "Article", "publisher" => { "parent" => { "datePublished" => "2024-03-15" } } }
    html = %(<script type="application/ld+json">#{nested.to_json}</script>)
    assert_equal Date.new(2024, 3, 15), extract(html)
  end

  # ---------------------------------------------------------------------------
  # Relative date handling
  # ---------------------------------------------------------------------------

  test "extracts '2 days ago' from bare <time> element" do
    html = "<time>2 days ago</time>"
    # Needs freeze_time or stubbing Date.current for determinism
    travel_to Date.new(2024, 6, 15) do
      assert_equal Date.new(2024, 6, 13), extract(html)
    end
  end

  test "extracts 'yesterday' from class-matched element" do
    html = '<span class="published">yesterday</span>'
    travel_to Date.new(2024, 6, 15) do
      assert_equal Date.new(2024, 6, 14), extract(html)
    end
  end

  test "validates relative date in meta tag (should be ISO only)" do
    travel_to Date.new(2024, 6, 15) do
      html = '<meta property="article:published_time" content="2 days ago">'
      assert_equal Date.new(2024, 6, 13), extract(html)
    end
  end

  test "ignores relative date in JSON-LD datePublished" do
    travel_to Date.new(2024, 6, 15) do
      html = <<~HTML
        <script type="application/ld+json">
          {"@type":"Article","datePublished":"2 days ago"}
        </script>
      HTML
      assert_equal Date.new(2024, 6, 13), extract(html)
    end
  end

  test "real ISO date in meta wins over relative in <time>" do
    html = <<~HTML
      <meta property="article:published_time" content="2024-03-15">
      <time>yesterday</time>
    HTML
    travel_to Date.new(2024, 6, 15) do
      assert_equal Date.new(2024, 3, 15), extract(html)
    end
  end

  test "returns date when first date candidate is relative" do
    html = <<~HTML
      <time>2 hours ago</time>
      <span class="date">yesterday</span>
      <meta property="article:published_time" content="invalid">
    HTML
    travel_to Date.new(2024, 6, 15) do
      assert_equal Date.new(2024, 6, 15), extract(html)
    end
  end

  test "partial date return current year" do
    html = <<~HTML
      <time>May 15</time>
    HTML
    assert_equal Date.parse("May 15"), extract(html)
  end

  test "complex nested extraction" do
    html = <<~HTML
      <li style="list-style:none;margin:0;padding:0">
        <a href="/books/a-marriage-at-sea/" class="post-card books-theme post-card-small">
          <div class="post-card-image post-card-image-small"></div>
          <div class="post-card-content">
            <div class="post-card-header">
              <span class="post-card-category books-theme">books</span>
              <div class="post-card-title-row">
                <h3 class="post-card-title">A Marriage At Sea</h3>
              </div>
            </div>
            <div class="post-card-date">13 Jan</div>
          </div>
        </a>
      </li>
    HTML
    assert_equal Date.parse("Jan 13"), extract(html)
  end

  test "antirez date extraction" do
    url = "https://antirez.com/latest/0"
    html = <<~HTML
      <article class="comment" style="margin-left:0px" data-comment-id="163-" id="163-">
        <span class="info">
          <span class="username">
            <a href="/user/antirez">antirez</a>
          </span>
          5 days ago. 83651 views.
        </span>
        <pre>The p</pre>
      </article>
    HTML
    travel_to Date.new(2025, 10, 19) do
      date = extract(html, url: url, base_url: "https://antirez.com")
      assert_equal Date.new(2025, 10, 14), date
    end
  end

  # ---------------------------------------------------------------------------
  # URL date parsing (extract_date_from_path / extract_date_from_url)
  # ---------------------------------------------------------------------------

  def path_date(path)
    WebProcessor::DateExtractor.extract_date_from_path(path)
  end

  # Year-first (ISO 8601 and slash variants) ---------------------------------

  test "parses YYYY/MM/DD slash dates" do
    assert_equal Date.new(2025, 7, 13), path_date("/2025/07/13/")
    assert_equal Date.new(2011, 7, 4), path_date("/2011/07/04/july-4")
  end

  test "parses single-digit month and day segments" do
    assert_equal Date.new(2024, 1, 5), path_date("/2024/1/5/post-title")
  end

  test "parses ISO 8601 dashed dates in the path" do
    assert_equal Date.new(2024, 1, 15), path_date("/2024-01-15-my-post")
    assert_equal Date.new(2024, 1, 15), path_date("/posts/2024-01-15/my-post")
  end

  test "parses dates that are not anchored to the path root" do
    assert_equal Date.new(2024, 1, 15), path_date("/blog/2024/01/15/slug")
    assert_equal Date.new(2024, 1, 15), path_date("/posts/2024/01/15")
  end

  test "swaps month and day when the year-first order is invalid" do
    # /2024/15/03 cannot be month=15; falls back to month=03, day=15.
    assert_equal Date.new(2024, 3, 15), path_date("/2024/15/03/post")
  end

  # Year-last (regional day/month-first) -------------------------------------

  test "parses European day-first dates with year last" do
    assert_equal Date.new(2024, 1, 15), path_date("/15-01-2024/post")
    assert_equal Date.new(2024, 1, 15), path_date("/15/01/2024/post")
  end

  test "parses US month-first dates when the day is unambiguous" do
    # 15 cannot be a month, so /01/15/2024 resolves to month=01, day=15.
    assert_equal Date.new(2024, 1, 15), path_date("/01/15/2024/post")
  end

  test "assumes day-first for ambiguous year-last dates" do
    # Both segments <= 12: /05/06/2024 is read as 5 June, not 6 May.
    assert_equal Date.new(2024, 6, 5), path_date("/05/06/2024/post")
  end

  # Year-month (month-level archives) ----------------------------------------

  test "parses month-level archives with no day" do
    assert_equal Date.new(2024, 1, 1), path_date("/2024/01/")
    assert_equal Date.new(2024, 1, 1), path_date("/2024-01")
  end

  test "prefers a full day-level date over the month-level fallback" do
    assert_equal Date.new(2024, 1, 15), path_date("/2024/01/15/slug")
  end

  # Rejections ---------------------------------------------------------------

  test "returns nil for paths without a date" do
    assert_nil path_date("/about")
    assert_nil path_date("/blog/why-react-re-renders")
    assert_nil path_date("")
  end

  test "rejects out-of-range numeric segments that look date-ish" do
    assert_nil path_date("/2024/77/88/x")
    assert_nil path_date("/2024/13/32/x")
  end

  test "rejects years outside the plausible 19xx/20xx range" do
    assert_nil path_date("/1234/01/15/x")
    assert_nil path_date("/9999/01/15/x")
  end

  test "extract_date_from_url resolves relative urls before parsing" do
    date = WebProcessor::DateExtractor.extract_date_from_url("/2024/01/15/post", "https://example.com")
    assert_equal Date.new(2024, 1, 15), date
  end

  test "extract_date_from_url returns nil when the url has no path date" do
    assert_nil WebProcessor::DateExtractor.extract_date_from_url("/latest/0", "https://example.com")
  end
end
