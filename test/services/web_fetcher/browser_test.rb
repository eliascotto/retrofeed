require "test_helper"

class WebFetcher::BrowserTest < ActiveSupport::TestCase
  setup do
    # Store original BrowserScraper methods
    @original_fetch = BrowserScraper.instance_method(:fetch)
    @original_fetch_with_scroll = BrowserScraper.instance_method(:fetch_with_scroll)
    @original_with_browser = BrowserScraper.instance_method(:with_browser)
    @original_navigate_to = BrowserScraper.instance_method(:navigate_to)
  end

  teardown do
    # Restore original methods
    BrowserScraper::Pool.shutdown_current_thread()
    BrowserScraper.define_method(:fetch, @original_fetch)
    BrowserScraper.define_method(:fetch_with_scroll, @original_fetch_with_scroll)
    BrowserScraper.define_method(:with_browser, @original_with_browser)
    BrowserScraper.define_method(:navigate_to, @original_navigate_to)
  end

  test "fetch returns content and final_url" do
    BrowserScraper.define_method(:fetch) do |url, wait_for_idle: true|
      { content: "<html>Mock content</html>", final_url: url }
    end

    result = WebFetcher::Browser.fetch("https://example.com/page")

    assert_equal "<html>Mock content</html>", result[:content]
    assert_equal "https://example.com/page", result[:final_url]
  end

  test "fetch raises FetchError on BrowserError" do
    BrowserScraper.define_method(:fetch) do |url, wait_for_idle: true|
      raise BrowserScraper::BrowserError, "Browser failed"
    end

    error = assert_raises(WebFetcher::FetchError) do
      WebFetcher::Browser.fetch("https://example.com/page")
    end

    assert_includes error.message, "Browser failed"
    assert_equal "https://example.com/page", error.url
    assert_equal "GET", error.http_method
  end

  test "fetch raises FetchError on BrowserCrashedError" do
    BrowserScraper.define_method(:fetch) do |url, wait_for_idle: true|
      raise BrowserScraper::BrowserCrashedError, "Browser crashed"
    end

    error = assert_raises(WebFetcher::FetchError) do
      WebFetcher::Browser.fetch("https://example.com/page")
    end

    assert_includes error.message, "crashed"
  end

  test "fetch raises FetchError on BrowserStartError" do
    BrowserScraper.define_method(:fetch) do |url, wait_for_idle: true|
      raise BrowserScraper::BrowserStartError, "Failed to start"
    end

    error = assert_raises(WebFetcher::FetchError) do
      WebFetcher::Browser.fetch("https://example.com/page")
    end

    assert_includes error.message, "start"
  end

  test "fetch_with_scroll returns content, final_url, and scroll_count" do
    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      {
        content: "<html>Scrolled content</html>",
        final_url: url,
        scroll_count: 5
      }
    end

    result = WebFetcher::Browser.fetch_with_scroll(
      "https://example.com/infinite",
      max_scrolls: 10
    )

    assert_equal "<html>Scrolled content</html>", result[:content]
    assert_equal "https://example.com/infinite", result[:final_url]
    assert_equal 5, result[:scroll_count]
  end

  test "fetch_with_scroll passes scroll options" do
    captured_options = nil
    BrowserScraper.define_method(:fetch_with_scroll) do |url, **options|
      captured_options = options
      { content: "<html></html>", final_url: url, scroll_count: 1 }
    end

    WebFetcher::Browser.fetch_with_scroll(
      "https://example.com/page",
      max_scrolls: 20,
      scroll_wait: 1.5,
      scroll_distance: 500
    )

    assert_equal 20, captured_options[:max_scrolls]
    assert_equal 1.5, captured_options[:scroll_wait]
    assert_equal 500, captured_options[:scroll_distance]
  end

  test "head returns status, headers, and final_url" do
    mock_browser = Struct.new(:current_url).new("https://example.com/page")

    BrowserScraper.define_method(:with_browser) do |&block|
      block.call(mock_browser)
    end

    BrowserScraper.define_method(:navigate_to) do |url, wait_for_idle: true|
      mock_browser.current_url = url
    end

    result = WebFetcher::Browser.head("https://example.com/page")

    assert_equal 200, result[:status]
    assert_equal({ "content-type" => "text/html" }, result[:headers])
    assert_equal "https://example.com/page", result[:final_url]
  end

  test "head raises FetchError on BrowserError" do
    BrowserScraper.define_method(:with_browser) do |&block|
      raise BrowserScraper::BrowserError, "Browser failed"
    end

    error = assert_raises(WebFetcher::FetchError) do
      WebFetcher::Browser.head("https://example.com/page")
    end

    assert_equal "HEAD", error.http_method
  end

  test "two successive WebFetcher::Browser.fetch calls reuse the same BrowserScraper instance" do
    fetches = []
    BrowserScraper.define_method(:fetch) do |url, wait_for_idle: true|
      fetches << self
      { content: "<html>Mock content</html>", final_url: url }
    end

    WebFetcher::Browser.fetch("https://example.com/page1")
    WebFetcher::Browser.fetch("https://example.com/page2")

    assert_equal 2, fetches.length
    assert_equal fetches[0], fetches[1]
  end
end
