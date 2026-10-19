require "test_helper"

class InfiniteScrollScraperTest < ActiveSupport::TestCase
  setup do
    @url = "https://example.com/blog"

    # Store original BrowserScraper method
    @original_fetch_with_scroll = BrowserScraper.instance_method(:fetch_with_scroll)

    # Store original WebProcessor method
    @original_extract = WebProcessor.method(:extract_articles_from_archive)
  end

  teardown do
    # Restore original methods
    BrowserScraper.define_method(:fetch_with_scroll, @original_fetch_with_scroll)
    WebProcessor.define_singleton_method(:extract_articles_from_archive, @original_extract)
  end

  test "DEFAULT_OPTIONS has reasonable defaults" do
    options = InfiniteScrollScraper::DEFAULT_OPTIONS
    assert_equal 10, options[:max_scrolls]
    assert_equal 2.0, options[:scroll_wait]
    assert_equal 1000, options[:scroll_distance]
    assert_equal 3, options[:no_new_content_threshold]
    assert options[:extract_articles]
  end

  test "initialize stores url and options" do
    scraper = InfiniteScrollScraper.new(url: @url, max_scrolls: 20)

    assert_equal @url, scraper.url
    assert_equal 20, scraper.options[:max_scrolls]
  end

  test "scrape returns html, final_url, and scroll_count" do
    mock_html = <<~HTML
      <html>
        <body>
          <article><a href="/post/1">Post 1</a></article>
        </body>
      </html>
    HTML

    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      { content: mock_html, final_url: url, scroll_count: 3 }
    end

    WebProcessor.define_singleton_method(:extract_articles_from_archive) do |html, url|
      { articles: [ { title: "Post 1", url: "https://example.com/post/1" } ] }
    end

    scraper = InfiniteScrollScraper.new(url: @url)
    result = scraper.scrape

    assert_equal mock_html, result[:html]
    assert_equal @url, result[:final_url]
    assert_equal 3, result[:scroll_count]
    assert_not_nil result[:fetched_at]
  end

  test "scrape extracts articles when extract_articles is true" do
    mock_html = "<html><body>Content</body></html>"

    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      { content: mock_html, final_url: url, scroll_count: 1 }
    end

    WebProcessor.define_singleton_method(:extract_articles_from_archive) do |html, url|
      { articles: [
        { title: "Article 1", url: "https://example.com/1" },
        { title: "Article 2", url: "https://example.com/2" }
      ] }
    end

    scraper = InfiniteScrollScraper.new(url: @url, extract_articles: true)
    result = scraper.scrape

    assert_equal 2, result[:articles].length
    assert_equal "Article 1", result[:articles][0][:title]
  end

  test "scrape skips article extraction when extract_articles is false" do
    mock_html = "<html><body>Content</body></html>"

    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      { content: mock_html, final_url: url, scroll_count: 1 }
    end

    scraper = InfiniteScrollScraper.new(url: @url, extract_articles: false)
    result = scraper.scrape

    assert_nil result[:articles]
  end

  test "scrape passes scroll options to BrowserScraper" do
    captured_options = nil

    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      captured_options = options
      { content: "<html></html>", final_url: url, scroll_count: 1 }
    end

    WebProcessor.define_singleton_method(:extract_articles_from_archive) do |html, url|
      { articles: [] }
    end

    scraper = InfiniteScrollScraper.new(
      url: @url,
      max_scrolls: 15,
      scroll_wait: 1.0,
      scroll_distance: 500,
      no_new_content_threshold: 2
    )
    scraper.scrape

    assert_equal 15, captured_options[:max_scrolls]
    assert_equal 1.0, captured_options[:scroll_wait]
    assert_equal 500, captured_options[:scroll_distance]
    assert_equal 2, captured_options[:no_new_content_threshold]
  end

  test "scrape raises ScrapingError on BrowserError" do
    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      raise BrowserScraper::BrowserError, "Browser failed"
    end

    scraper = InfiniteScrollScraper.new(url: @url)

    error = assert_raises(InfiniteScrollScraper::ScrapingError) do
      scraper.scrape
    end

    assert_includes error.message, "Browser error"
  end

  test "each_page yields page data" do
    mock_html = <<~HTML
      <html>
        <body>
          <article><a href="/post/1">Post 1</a></article>
        </body>
      </html>
    HTML

    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      { content: mock_html, final_url: url, scroll_count: 5 }
    end

    WebProcessor.define_singleton_method(:extract_articles_from_archive) do |html, url|
      { articles: [ { title: "Post 1", url: "https://example.com/post/1" } ] }
    end

    scraper = InfiniteScrollScraper.new(url: @url)
    yielded_data = nil

    scraper.each_page do |page_number, page_url, html, articles_data|
      yielded_data = {
        page_number: page_number,
        page_url: page_url,
        html: html,
        articles_count: articles_data.length
      }
    end

    assert_equal 1, yielded_data[:page_number]
    assert_equal @url, yielded_data[:page_url]
    assert_instance_of Nokogiri::HTML::Document, yielded_data[:html]
    assert_equal 1, yielded_data[:articles_count]
  end

  test "completed? returns false before scrape" do
    scraper = InfiniteScrollScraper.new(url: @url)
    assert_not scraper.completed?
  end

  test "completed? returns true after scrape" do
    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      { content: "<html></html>", final_url: url, scroll_count: 1 }
    end

    WebProcessor.define_singleton_method(:extract_articles_from_archive) do |html, url|
      { articles: [] }
    end

    scraper = InfiniteScrollScraper.new(url: @url)
    scraper.scrape

    assert scraper.completed?
  end

  # Test error class
  test "ScrapingError is a StandardError" do
    assert InfiniteScrollScraper::ScrapingError < StandardError
  end

  # Integration test with infinite scroll fixture
  # This test simulates what the browser would return after scrolling
  test "scrape extracts all articles from infinite scroll page after scrolling" do
    # Build the fully-loaded HTML that simulates what the browser returns after scrolling
    # The fixture starts with 5 articles and loads 10 more through JavaScript
    fully_loaded_html = build_fully_scrolled_html

    scroll_count = 0

    # Mock BrowserScraper to simulate scrolling behavior
    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      max_scrolls = options[:max_scrolls] || 10
      no_new_content_threshold = options[:no_new_content_threshold] || 3

      # Simulate scrolling: we need about 4 scrolls to load all content (3 batches of 3 articles each)
      # Then 3 more scrolls with no new content to trigger the threshold
      scroll_count = [ max_scrolls, 4 + no_new_content_threshold ].min

      { content: fully_loaded_html, final_url: url, scroll_count: scroll_count }
    end

    scraper = InfiniteScrollScraper.new(
      url: "https://infinite-scroll-test.example.com/",
      max_scrolls: 10,
      scroll_wait: 0.1,
      no_new_content_threshold: 3
    )

    result = scraper.scrape

    # Verify all 15 articles were extracted
    assert_equal 15, result[:articles].length, "Expected 15 articles to be extracted"

    # Verify articles have proper structure
    first_article = result[:articles].first
    assert first_article[:title].present?, "Article should have a title"
    assert first_article[:url].present?, "Article should have a URL"

    # Verify article titles match expected
    titles = result[:articles].map { |a| a[:title] }
    assert_includes titles, "Understanding Infinite Scroll Patterns"
    assert_includes titles, "Building Resilient Systems"

    # Verify scroll count is reasonable (not infinite loop)
    assert result[:scroll_count] >= 4, "Should scroll at least 4 times to load all content"
    assert result[:scroll_count] <= 10, "Should not exceed max_scrolls limit"

    # Verify the scraper completed
    assert scraper.completed?
  end

  test "infinite scroll respects max_scrolls limit" do
    fully_loaded_html = build_fully_scrolled_html
    captured_max_scrolls = nil

    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      captured_max_scrolls = options[:max_scrolls]
      { content: fully_loaded_html, final_url: url, scroll_count: options[:max_scrolls] }
    end

    scraper = InfiniteScrollScraper.new(
      url: "https://infinite-scroll-test.example.com/",
      max_scrolls: 5
    )
    result = scraper.scrape

    assert_equal 5, captured_max_scrolls
    assert_equal 5, result[:scroll_count]
  end

  test "infinite scroll stops when no new content is detected" do
    # Simulate a page where content stops loading after 2 scrolls
    partial_html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Partial Scroll</title></head>
      <body>
        <ul class="post-list" id="articles">
          <li>
            <span class="post-meta">Jan 15, 2026</span>
            <h3><a class="post-link" href="/articles/article-1">Article One</a></h3>
          </li>
          <li>
            <span class="post-meta">Jan 10, 2026</span>
            <h3><a class="post-link" href="/articles/article-2">Article Two</a></h3>
          </li>
          <li>
            <span class="post-meta">Jan 5, 2026</span>
            <h3><a class="post-link" href="/articles/article-3">Article Three</a></h3>
          </li>
        </ul>
      </body>
      </html>
    HTML

    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      # Simulate stopping after 2 scrolls + threshold
      no_new_content_threshold = options[:no_new_content_threshold] || 3
      scroll_count = 2 + no_new_content_threshold
      { content: partial_html, final_url: url, scroll_count: scroll_count }
    end

    scraper = InfiniteScrollScraper.new(
      url: "https://example.com/partial-scroll",
      max_scrolls: 20,
      no_new_content_threshold: 3
    )
    result = scraper.scrape

    # Should have 3 articles
    assert_equal 3, result[:articles].length

    # Scroll count should be 5 (2 productive scrolls + 3 threshold)
    assert_equal 5, result[:scroll_count]
  end

  private

  # Builds HTML that represents the fully-scrolled state of the infinite scroll fixture
  # This simulates what a browser would return after scrolling to load all content
  def build_fully_scrolled_html
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Infinite Scroll Blog Archive</title>
      </head>
      <body>
        <header>
          <h1>Infinite Scroll Blog</h1>
        </header>
        <main>
          <h2>Posts</h2>
          <ul class="post-list" id="articles">
            <li>
              <span class="post-meta">Jan 15, 2026</span>
              <h3><a class="post-link" href="/articles/article-1">Understanding Infinite Scroll Patterns</a></h3>
            </li>
            <li>
              <span class="post-meta">Jan 10, 2026</span>
              <h3><a class="post-link" href="/articles/article-2">Building Dynamic Web Applications</a></h3>
            </li>
            <li>
              <span class="post-meta">Jan 5, 2026</span>
              <h3><a class="post-link" href="/articles/article-3">JavaScript Event Handling Best Practices</a></h3>
            </li>
            <li>
              <span class="post-meta">Dec 28, 2025</span>
              <h3><a class="post-link" href="/articles/article-4">Modern CSS Layout Techniques</a></h3>
            </li>
            <li>
              <span class="post-meta">Dec 20, 2025</span>
              <h3><a class="post-link" href="/articles/article-5">Web Performance Optimization Guide</a></h3>
            </li>
            <li>
              <span class="post-meta">Dec 15, 2025</span>
              <h3><a class="post-link" href="/articles/article-6">API Design Principles</a></h3>
            </li>
            <li>
              <span class="post-meta">Dec 10, 2025</span>
              <h3><a class="post-link" href="/articles/article-7">Database Optimization Strategies</a></h3>
            </li>
            <li>
              <span class="post-meta">Dec 5, 2025</span>
              <h3><a class="post-link" href="/articles/article-8">Container Orchestration Basics</a></h3>
            </li>
            <li>
              <span class="post-meta">Nov 28, 2025</span>
              <h3><a class="post-link" href="/articles/article-9">Microservices Architecture Patterns</a></h3>
            </li>
            <li>
              <span class="post-meta">Nov 20, 2025</span>
              <h3><a class="post-link" href="/articles/article-10">Test-Driven Development in Practice</a></h3>
            </li>
            <li>
              <span class="post-meta">Nov 15, 2025</span>
              <h3><a class="post-link" href="/articles/article-11">Security Best Practices for Web Apps</a></h3>
            </li>
            <li>
              <span class="post-meta">Nov 10, 2025</span>
              <h3><a class="post-link" href="/articles/article-12">Continuous Integration Pipeline Setup</a></h3>
            </li>
            <li>
              <span class="post-meta">Nov 5, 2025</span>
              <h3><a class="post-link" href="/articles/article-13">Monitoring and Observability</a></h3>
            </li>
            <li>
              <span class="post-meta">Oct 28, 2025</span>
              <h3><a class="post-link" href="/articles/article-14">Caching Strategies for Performance</a></h3>
            </li>
            <li>
              <span class="post-meta">Oct 20, 2025</span>
              <h3><a class="post-link" href="/articles/article-15">Building Resilient Systems</a></h3>
            </li>
          </ul>
          <div id="end-message" style="display: block;">No more articles to load</div>
        </main>
      </body>
      </html>
    HTML
  end
end
