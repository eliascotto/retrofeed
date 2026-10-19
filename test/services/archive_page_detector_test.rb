require "test_helper"

class ArchivePageDetectorTest < ActiveSupport::TestCase
  DEFAULT_HOST = "https://example.com"

  setup do
    @valid_archive_html = <<~HTML
      <html>
        <head><title>Blog Archive</title></head>
        <body>
          <article><a href="/posts/one">Post One</a><time>2024-01-01</time></article>
          <article><a href="/posts/two">Post Two</a><time>2024-01-02</time></article>
          <article><a href="/posts/three">Post Three</a><time>2024-01-03</time></article>
          <article><a href="/posts/four">Post Four</a><time>2024-01-04</time></article>
          <article><a href="/posts/five">Post Five</a><time>2024-01-05</time></article>
        </body>
      </html>
    HTML

    @non_archive_html = <<~HTML
      <html>
        <head><title>About Us</title></head>
        <body>
          <h1>About this website</h1>
          <p>Some content here.</p>
        </body>
      </html>
    HTML

    @homepage_with_archive_link = <<~HTML
      <html>
        <head><title>My Blog</title></head>
        <body>
          <nav>
            <a href="/">Home</a>
            <a href="/archive">Archive</a>
            <a href="/about">About</a>
          </nav>
          <h1>Welcome</h1>
        </body>
      </html>
    HTML

    @paginated_archive_html = <<~HTML
      <html>
        <head>
          <title>Blog Archive</title>
          <link rel="next" href="/blog/page/2">
        </head>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
          <article><a href="/posts/three">Post Three</a></article>
          <article><a href="/posts/four">Post Four</a></article>
          <article><a href="/posts/five">Post Five</a></article>
          <nav class="pagination">
            <a href="/blog/page/2">Next</a>
          </nav>
        </body>
      </html>
    HTML
  end

  test "detects valid user-provided archive URL" do
    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: @valid_archive_html, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")

    assert_equal "#{DEFAULT_HOST}/blog", result.url
    assert_equal "user_provided", result.method
    assert_equal 1.0, result.confidence_score
    assert_equal false, result.pagination_detected
  end

  test "detects archive at known path when user URL is not archive" do
    stub_request(:get, "#{DEFAULT_HOST}/about")
      .to_return(body: @non_archive_html, status: 200)
    stub_request(:head, "#{DEFAULT_HOST}/archive")
      .to_return(status: 200, headers: { "content-type" => "text/html" })
    stub_request(:head, "#{DEFAULT_HOST}/archive.html")
      .to_return(status: 404)
    stub_request(:get, "#{DEFAULT_HOST}/archive")
      .to_return(body: @valid_archive_html, status: 200)

    stub_archive_common_paths(exclude: [ "archive" ])

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/about")

    assert_equal "#{DEFAULT_HOST}/archive", result.url
    assert_equal "known_path", result.method
    assert_equal 0.9, result.confidence_score
  end

  test "detects homepage as archive when it contains posts" do
    homepage_archive_html = <<~HTML
      <html>
        <head><title>My Blog</title></head>
        <body>
          <article><a href="/posts/one">Post One</a><time>2024-01-01</time></article>
          <article><a href="/posts/two">Post Two</a><time>2024-01-02</time></article>
          <article><a href="/posts/three">Post Three</a><time>2024-01-03</time></article>
          <article><a href="/posts/four">Post Four</a><time>2024-01-04</time></article>
          <article><a href="/posts/five">Post Five</a><time>2024-01-05</time></article>
        </body>
      </html>
    HTML

    # Single article pages (not archives)
    single_article_html = "<html><body><h1>Article</h1><p>Content</p></body></html>"

    stub_request(:get, "#{DEFAULT_HOST}/contact")
      .to_return(body: @non_archive_html, status: 200)

    # All known archive paths return 404
    stub_archive_common_paths

    # Individual article pages are not archives (now checked as candidates)
    %w[/posts/one /posts/two /posts/three /posts/four /posts/five].each do |path|
      stub_request(:get, "https://example.com#{path}")
        .to_return(body: single_article_html, status: 200)
    end

    # Origin page is an archive
    stub_request(:get, "https://example.com")
      .to_return(body: homepage_archive_html, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/contact")

    assert_equal "https://example.com", result.url
    assert_equal "link_analysis", result.method
    assert result.confidence_score >= 0.5
    assert_includes result.notes, "Homepage contains valid archive"
  end

  test "detects pagination in archive" do
    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: @paginated_archive_html, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")

    assert_equal "#{DEFAULT_HOST}/blog", result.url
    assert_equal true, result.pagination_detected
  end

  test "raises DetectionError when no archive found" do
    stub_request(:get, "#{DEFAULT_HOST}/about")
      .to_return(body: @non_archive_html, status: 200)

    stub_archive_common_paths

    # Origin page is not an archive and has no archive links
    stub_request(:get, "https://example.com")
      .to_return(body: @non_archive_html, status: 200)

    # Feed paths also return 404
    stub_feed_paths

    error = assert_raises(ArchivePageDetector::DetectionError) do
      ArchivePageDetector.detect("#{DEFAULT_HOST}/about")
    end

    assert_match(/could not detect/i, error.message)
  end

  test "follows archive links from navigation" do
    stub_request(:get, "#{DEFAULT_HOST}/")
      .to_return(body: @homepage_with_archive_link, status: 200)

    stub_archive_common_paths

    stub_request(:head, "#{DEFAULT_HOST}/archive")
      .to_return(status: 200, headers: { "content-type" => "text/html" })
    stub_request(:head, "#{DEFAULT_HOST}/archive.html")
      .to_return(status: 404)
    stub_request(:get, "#{DEFAULT_HOST}/archive")
      .to_return(body: @valid_archive_html, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/")

    # Since the homepage itself is not a valid archive, it should find /archive via known paths
    # or via link analysis
    assert_equal "#{DEFAULT_HOST}/archive", result.url
  end

  test "detects pagination via page number URLs" do
    html_with_page_links = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
          <article><a href="/posts/three">Post Three</a></article>
          <article><a href="/posts/four">Post Four</a></article>
          <article><a href="/posts/five">Post Five</a></article>
          <a href="/blog/page/2">Page 2</a>
          <a href="/blog/page/3">Page 3</a>
        </body>
      </html>
    HTML

    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: html_with_page_links, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")

    assert_equal true, result.pagination_detected
  end

  test "detects pagination via query string page parameter" do
    html_with_query_pagination = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
          <article><a href="/posts/three">Post Three</a></article>
          <article><a href="/posts/four">Post Four</a></article>
          <article><a href="/posts/five">Post Five</a></article>
          <a href="/blog?page=2">Next</a>
        </body>
      </html>
    HTML

    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: html_with_query_pagination, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")

    assert_equal true, result.pagination_detected
  end

  test "detects pagination via offset parameter" do
    html_with_offset = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
          <article><a href="/posts/three">Post Three</a></article>
          <article><a href="/posts/four">Post Four</a></article>
          <article><a href="/posts/five">Post Five</a></article>
          <a href="/blog?offset=20">Load More</a>
        </body>
      </html>
    HTML

    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: html_with_offset, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")

    assert_equal true, result.pagination_detected
  end

  test "detects pagination via cursor parameter" do
    html_with_cursor = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
          <article><a href="/posts/three">Post Three</a></article>
          <article><a href="/posts/four">Post Four</a></article>
          <article><a href="/posts/five">Post Five</a></article>
          <a href="/blog?cursor=abc123">Next</a>
        </body>
      </html>
    HTML

    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: html_with_cursor, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")

    assert_equal true, result.pagination_detected
  end

  test "detects pagination via 'Older posts' link text" do
    html_with_older = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
          <article><a href="/posts/three">Post Three</a></article>
          <article><a href="/posts/four">Post Four</a></article>
          <article><a href="/posts/five">Post Five</a></article>
          <a href="/archive/2">Older posts</a>
        </body>
      </html>
    HTML

    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: html_with_older, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")

    assert_equal true, result.pagination_detected
  end

  test "detects pagination via aria-label on container" do
    html_with_aria = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
          <article><a href="/posts/three">Post Three</a></article>
          <article><a href="/posts/four">Post Four</a></article>
          <article><a href="/posts/five">Post Five</a></article>
          <nav aria-label="Pagination">
            <span>1</span>
            <a href="/archive/2">2</a>
          </nav>
        </body>
      </html>
    HTML

    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: html_with_aria, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")

    assert_equal true, result.pagination_detected
  end

  test "handles network errors gracefully" do
    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_timeout

    stub_archive_common_paths(timeout: true)

    stub_request(:get, "https://example.com").to_timeout

    # Feed paths also fail
    stub_feed_paths(timeout: true)

    error = assert_raises(ArchivePageDetector::DetectionError) do
      ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")
    end

    assert_match(/could not detect/i, error.message)
  end

  test "Result struct has all required fields" do
    result = ArchivePageDetector::Result.new(
      url: "#{DEFAULT_HOST}/archive",
      method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false,
      notes: "Test"
    )

    assert_equal "#{DEFAULT_HOST}/archive", result.url
    assert_equal "user_provided", result.method
    assert_equal 1.0, result.confidence_score
    assert_equal false, result.pagination_detected
    assert_equal "Test", result.notes
  end

  test "prefers dedicated /blog page over homepage with articles" do
    # Homepage has some article links (looks like a valid archive)
    homepage_with_articles = <<~HTML
      <html>
        <head><title>My Site</title></head>
        <body>
          <nav>
            <a href="/">Home</a>
            <a href="/blog">Blog</a>
            <a href="/about">About</a>
          </nav>
          <h1>Welcome to my site</h1>
          <h2>Recent Posts</h2>
          <article><a href="/2024/01/post-one">Post One</a><time>2024-01-01</time></article>
          <article><a href="/2024/01/post-two">Post Two</a><time>2024-01-02</time></article>
          <article><a href="/2024/01/post-three">Post Three</a><time>2024-01-03</time></article>
          <article><a href="/2024/01/post-four">Post Four</a><time>2024-01-04</time></article>
          <article><a href="/2024/01/post-five">Post Five</a><time>2024-01-05</time></article>
        </body>
      </html>
    HTML

    # Dedicated blog page has more articles and pagination (the full archive)
    blog_archive = <<~HTML
      <html>
        <head>
          <title>Blog Archive</title>
          <link rel="next" href="/blog/page/2">
        </head>
        <body>
          <h1>All Blog Posts</h1>
          <article><a href="/2024/01/post-one">Post One</a><time>2024-01-01</time></article>
          <article><a href="/2024/01/post-two">Post Two</a><time>2024-01-02</time></article>
          <article><a href="/2024/01/post-three">Post Three</a><time>2024-01-03</time></article>
          <article><a href="/2024/01/post-four">Post Four</a><time>2024-01-04</time></article>
          <article><a href="/2024/01/post-five">Post Five</a><time>2024-01-05</time></article>
          <article><a href="/2023/12/post-six">Post Six</a><time>2023-12-15</time></article>
          <article><a href="/2023/12/post-seven">Post Seven</a><time>2023-12-10</time></article>
          <nav class="pagination">
            <a href="/blog/page/2">Older posts</a>
          </nav>
        </body>
      </html>
    HTML

    # User provides homepage URL
    stub_request(:get, "#{DEFAULT_HOST}/")
      .to_return(body: homepage_with_articles, status: 200)

    # /blog exists and is a valid archive with pagination
    stub_request(:head, "#{DEFAULT_HOST}/blog")
      .to_return(status: 200)
    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: blog_archive, status: 200)

    # Other known paths return 404
    stub_archive_common_paths(exclude: [ "blog" ])

    stub_request(:head, "#{DEFAULT_HOST}/blog.html")
      .to_return(status: 404)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/")

    # Should prefer /blog over homepage because it's a dedicated archive page
    assert_equal "#{DEFAULT_HOST}/blog", result.url
    assert_equal "known_path", result.method
    assert result.pagination_detected, "Should detect pagination on /blog"
  end

  test "prefers /blog/ with trailing slash over homepage when homepage contains articles" do
    # Homepage has some article links (looks like a valid archive)
    homepage_with_articles = <<~HTML
      <html>
        <head><title>Candost Blog</title></head>
        <body>
          <h1>Welcome</h1>
          <article><a href="/2024/01/post-one">Post One</a><time>2024-01-01</time></article>
          <article><a href="/2024/01/post-two">Post Two</a><time>2024-01-02</time></article>
          <article><a href="/2024/01/post-three">Post Three</a><time>2024-01-03</time></article>
        </body>
      </html>
    HTML

    # Dedicated blog page at /blog/ (with trailing slash) is the actual archive
    blog_archive = <<~HTML
      <html>
        <head>
          <title>Blog Archive</title>
          <link rel="next" href="/blog/page/2">
        </head>
        <body>
          <h1>All Blog Posts</h1>
          <article><a href="/2024/01/post-one">Post One</a><time>2024-01-01</time></article>
          <article><a href="/2024/01/post-two">Post Two</a><time>2024-01-02</time></article>
          <article><a href="/2024/01/post-three">Post Three</a><time>2024-01-03</time></article>
          <article><a href="/2023/12/post-four">Post Four</a><time>2023-12-15</time></article>
          <article><a href="/2023/12/post-five">Post Five</a><time>2023-12-10</time></article>
          <nav class="pagination">
            <a href="/blog/page/2">Older posts</a>
          </nav>
        </body>
      </html>
    HTML

    # User provides homepage URL (UrlUtils normalizes to trailing slash)
    stub_request(:get, "https://candost.blog/")
      .to_return(body: homepage_with_articles, status: 200)

    # /blog redirects to /blog/ (with trailing slash)
    # HTTParty automatically follows redirects, so we need to stub the redirect chain
    # First, stub HEAD to /blog to redirect to /blog/
    stub_request(:head, "https://candost.blog/blog")
      .to_return(status: 301, headers: { "Location" => "https://candost.blog/blog/" })
    # HTTParty will automatically follow the redirect and make another HEAD to /blog/
    stub_request(:head, "https://candost.blog/blog/")
      .to_return(status: 200, headers: { "content-type" => "text/html" })
    # GET request to /blog/ for full content
    stub_request(:get, "https://candost.blog/blog/")
      .to_return(body: blog_archive, status: 200)

    stub_archive_common_paths(exclude: [ "blog" ], host: "https://candost.blog")

    stub_request(:head, "https://candost.blog/blog.html")
      .to_return(status: 404)

    # Feed paths (for Strategy D fallback - should not be reached)
    stub_feed_paths(host: "https://candost.blog")

    result = ArchivePageDetector.detect("https://candost.blog")

    # Should prefer /blog/ (with trailing slash) over homepage
    # The app should try to find the archive first and not stop at the homepage
    assert_equal "https://candost.blog/blog/", result.url
    assert_equal "known_path", result.method
    assert result.pagination_detected, "Should detect pagination on /blog/"
  end

  # Regression: patshaughnessy.net homepage was returning an individual article as
  # the "archive". Article links became candidates via substring/keyword matching and
  # their post-listing sidebars passed contains_valid_archive?, so a weak article
  # candidate displaced the homepage. The homepage itself must win.
  test "keeps homepage as archive instead of an article that merely lists posts" do
    homepage_archive_html = <<~HTML
      <html>
        <head><title>Pat's Blog</title></head>
        <body>
          <article><a href="/2025/11/3/compiling-a-call-to-a-block">Compiling a Call to a Block</a><time>2025-11-03</time></article>
          <article><a href="/2019/9/4/using-rust-to-build-a-blog-site">Using Rust to Build a Blog Site</a><time>2019-09-04</time></article>
          <article><a href="/2017/12/12/installing-the-postgres-ltree">Installing the Postgres LTREE Extension</a><time>2017-12-12</time></article>
          <article><a href="/2015/1/8/using-rake-to-generate-a-blog">Using Rake to Generate a Blog</a><time>2015-01-08</time></article>
          <article><a href="/2013/6/4/coming-this-fall-ruby-under-a-microscope">Coming This Fall</a><time>2013-06-04</time></article>
          <a href="/my-blog-post">Read my blog post</a>
        </body>
      </html>
    HTML

    # An individual article whose body lists other posts in a sidebar, so it would
    # pass contains_valid_archive?. Reached via a keyword link ("blog") that is not a
    # dated URL, so it survives the candidate filter and exercises the homepage gate.
    article_with_sidebar_html = <<~HTML
      <html>
        <head><title>My Blog Post</title></head>
        <body>
          <h1>My Blog Post</h1>
          <aside>
            <a href="/posts/one">Post One</a>
            <a href="/posts/two">Post Two</a>
            <a href="/posts/three">Post Three</a>
            <a href="/posts/four">Post Four</a>
            <a href="/posts/five">Post Five</a>
          </aside>
        </body>
      </html>
    HTML

    stub_request(:get, "#{DEFAULT_HOST}/contact")
      .to_return(body: @non_archive_html, status: 200)
    stub_archive_common_paths
    stub_feed_paths

    stub_request(:get, "https://example.com")
      .to_return(body: homepage_archive_html, status: 200)
    stub_request(:get, "#{DEFAULT_HOST}/my-blog-post")
      .to_return(body: article_with_sidebar_html, status: 200)

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/contact")

    assert_equal "https://example.com", result.url
    assert_equal "link_analysis", result.method
    assert_includes result.notes, "Homepage contains valid archive"
  end

  test "uses the injected fetcher instead of the default WebFetcher" do
    # A fake fetcher that records its calls and serves the archive HTML.
    # No webmock stubs are registered, so if detection touched the default
    # WebFetcher (real HTTP) the test would fail on an unregistered request.
    archive_html = @valid_archive_html
    fake_fetcher = Object.new
    fake_fetcher.define_singleton_method(:fetched_urls) { @fetched_urls ||= [] }
    fake_fetcher.define_singleton_method(:fetch) do |url|
      fetched_urls << url
      { content: archive_html, final_url: url }
    end
    fake_fetcher.define_singleton_method(:head) do |url|
      { status: 200, headers: { "content-type" => "text/html" }, final_url: url }
    end

    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog", fetcher: fake_fetcher)

    assert_equal "#{DEFAULT_HOST}/blog", result.url
    assert_equal "user_provided", result.method
    assert_includes fake_fetcher.fetched_urls, "#{DEFAULT_HOST}/blog"
  end

  test "records a detection decision log when the thread-local is set" do
    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: @valid_archive_html, status: 200)

    Thread.current[:playground_detection_log] = []
    result = ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")
    log = Thread.current[:playground_detection_log]

    accepted = log.find { |entry| entry[:accepted] }
    assert accepted, "Expected an accepted decision entry"
    assert_equal result.method, accepted[:strategy]
    assert_equal result.url, accepted[:candidate_url]
    assert accepted[:reason].present?
    assert_equal result.confidence_score, accepted[:score]
  ensure
    Thread.current[:playground_detection_log] = nil
  end

  test "records reject decisions before the accepted strategy" do
    stub_request(:get, "#{DEFAULT_HOST}/about")
      .to_return(body: @non_archive_html, status: 200)
    stub_request(:head, "#{DEFAULT_HOST}/archive")
      .to_return(status: 200, headers: { "content-type" => "text/html" })
    stub_request(:get, "#{DEFAULT_HOST}/archive")
      .to_return(body: @valid_archive_html, status: 200)

    stub_archive_common_paths(exclude: [ "archive" ])

    stub_request(:head, "#{DEFAULT_HOST}/archive.html").to_return(status: 404)

    Thread.current[:playground_detection_log] = []
    ArchivePageDetector.detect("#{DEFAULT_HOST}/about")
    log = Thread.current[:playground_detection_log]

    assert log.any? { |entry| entry[:strategy] == "user_provided" && !entry[:accepted] }
    assert log.any? { |entry| entry[:strategy] == "known_path" && entry[:accepted] }
  ensure
    Thread.current[:playground_detection_log] = nil
  end

  test "does not log when the thread-local is not set" do
    stub_request(:get, "#{DEFAULT_HOST}/blog")
      .to_return(body: @valid_archive_html, status: 200)

    assert_nil Thread.current[:playground_detection_log]
    ArchivePageDetector.detect("#{DEFAULT_HOST}/blog")
    assert_nil Thread.current[:playground_detection_log]
  end

  private
    # Stub other known paths to return 404, or timeout if specified
    def stub_archive_common_paths(exclude: [], timeout: false, host: DEFAULT_HOST)
      (ArchivePageDetector::KNOWN_ARCHIVE_WORDS - exclude).each do |word|
        if timeout
          stub_request(:head, "#{host}/#{word}").to_timeout
          stub_request(:head, "#{host}/#{word}.html").to_timeout
        else
          stub_request(:head, "#{host}/#{word}").to_return(status: 404)
          stub_request(:head, "#{host}/#{word}.html").to_return(status: 404)
        end
      end
    end

    def stub_feed_paths(host: DEFAULT_HOST, timeout: false)
      feed_words = %w[feed rss atom]

      feed_words.each do |word|
        if timeout
          stub_request(:head, "#{host}/#{word}").to_timeout
          stub_request(:head, "#{host}/#{word}.xml").to_timeout
        else
          stub_request(:head, "#{host}/#{word}").to_return(status: 404)
          stub_request(:head, "#{host}/#{word}.xml").to_return(status: 404)
        end
      end
      # /index.xml
      if timeout
        stub_request(:head, "#{host}/index.xml").to_timeout
      else
        stub_request(:head, "#{host}/index.xml").to_return(status: 404)
      end
    end
end
