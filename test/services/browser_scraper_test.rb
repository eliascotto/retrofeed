require "test_helper"

class BrowserScraperTest < ActiveSupport::TestCase
  class MockBrowser
    class MockNetwork
      attr_reader :clear_called

      def initialize
        @clear_called = false
      end
      
      def clear(_type)
        @clear_called = true
      end

      def wait_for_idle(timeout: 30)
      end
    end

    attr_accessor :current_url, :body_content, :scroll_height, :reset_called, :network

    def initialize
      @current_url = "https://example.com"
      @body_content = "<html><body>Test</body></html>"
      @scroll_height = 1000
      @reset_called = false
      @network = MockNetwork.new
    end

    def go_to(url)
      @current_url = url
    end

    def body = @body_content

    def quit
    end

    def wait_for_idle(timeout: 30)
    end

    def execute(script)
      if script.include?("scrollBy")
        @scroll_height += 100
      end
    end

    def evaluate(script) = @scroll_height

    def process = self

    def pid = 12345

    def reset
      @reset_called = true
    end
  end

  setup do
    # Store original browser path
    @original_browser_path = ENV["BROWSER_PATH"]
  end

  teardown do
    # Restore original browser path
    if @original_browser_path
      ENV["BROWSER_PATH"] = @original_browser_path
    else
      ENV.delete("BROWSER_PATH")
    end
  end

  test "DEFAULT_OPTIONS has headless mode enabled" do
    assert BrowserScraper::DEFAULT_OPTIONS[:headless]
  end

  test "DEFAULT_OPTIONS has Docker-friendly browser options" do
    options = BrowserScraper::DEFAULT_OPTIONS[:browser_options]
    assert options.key?("no-sandbox")
    assert options.key?("disable-dev-shm-usage")
    assert options.key?("disable-gpu")
  end

  test "DEFAULT_SCROLL_OPTIONS has reasonable defaults" do
    options = BrowserScraper::DEFAULT_SCROLL_OPTIONS
    assert_equal 10, options[:max_scrolls]
    assert_equal 2.0, options[:scroll_wait]
    assert_equal 1000, options[:scroll_distance]
    assert_equal 3, options[:no_new_content_threshold]
  end

  test "initialize uses BROWSER_PATH environment variable" do
    ENV["BROWSER_PATH"] = "/custom/path/to/chrome"
    scraper = BrowserScraper.new
    assert_equal "/custom/path/to/chrome", scraper.options[:browser_path]
  end

  test "initialize merges custom options" do
    scraper = BrowserScraper.new(timeout: 60)
    assert_equal 60, scraper.options[:timeout]
    assert_equal true, scraper.options[:headless]  # Default preserved
  end

  test "browser is nil before start" do
    scraper = BrowserScraper.new
    assert_nil scraper.browser
  end

  test "quit is safe to call when browser not started" do
    scraper = BrowserScraper.new
    assert_nothing_raised { scraper.quit }
  end

  test "force_cleanup is safe to call when browser not started" do
    scraper = BrowserScraper.new
    assert_nothing_raised { scraper.force_cleanup }
  end

  # Test error class hierarchy
  test "BrowserError is a StandardError" do
    assert BrowserScraper::BrowserError < StandardError
  end

  test "NavigationError is a BrowserError" do
    assert BrowserScraper::NavigationError < BrowserScraper::BrowserError
  end

  test "BrowserCrashedError is a BrowserError" do
    assert BrowserScraper::BrowserCrashedError < BrowserScraper::BrowserError
  end

  test "BrowserStartError is a BrowserError" do
    assert BrowserScraper::BrowserStartError < BrowserScraper::BrowserError
  end

  test "BrowserTimeoutError is a BrowserError" do
    assert BrowserScraper::BrowserTimeoutError < BrowserScraper::BrowserError
  end

  test "extract_result returns content and final_url" do
    scraper = BrowserScraper.new
    mock_browser = MockBrowser.new
    mock_browser.current_url = "https://example.com/page"
    mock_browser.body_content = "<html><body>Content</body></html>"

    scraper.instance_variable_set(:@browser, mock_browser)
    scraper.instance_variable_set(:@started, true)

    result = scraper.extract_result

    assert_equal "<html><body>Content</body></html>", result[:content]
    assert_equal "https://example.com/page", result[:final_url]
  end

  test "extract_result raises BrowserError when browser not started" do
    scraper = BrowserScraper.new

    assert_raises(BrowserScraper::BrowserError) do
      scraper.extract_result
    end
  end

  test "perform_infinite_scroll raises BrowserError when browser not started" do
    scraper = BrowserScraper.new

    assert_raises(BrowserScraper::BrowserError) do
      scraper.perform_infinite_scroll(
        max_scrolls: 5,
        scroll_wait: 0.1,
        scroll_distance: 100,
        no_new_content_threshold: 2
      )
    end
  end

  test "get_scroll_height returns integer" do
    scraper = BrowserScraper.new
    mock_browser = MockBrowser.new
    mock_browser.scroll_height = 2500

    scraper.instance_variable_set(:@browser, mock_browser)
    scraper.instance_variable_set(:@started, true)

    height = scraper.get_scroll_height
    assert_kind_of Integer, height
    assert_equal 2500, height
  end

  test "fetch_count is incremented when fetch succeeds" do
    scraper = BrowserScraper.new
    mock_browser = MockBrowser.new
    mock_browser.current_url = "https://example.com/page"
    mock_browser.body_content = "<html><body>Content</body></html>"

    scraper.instance_variable_set(:@browser, mock_browser)
    scraper.instance_variable_set(:@started, true)

    assert_equal 0, scraper.instance_variable_get(:@fetch_count)

    scraper.fetch("https://example.com")

    assert_equal 1, scraper.instance_variable_get(:@fetch_count)
  end

  test "exhausted? is false on a fresh scraper" do
    scraper = BrowserScraper.new
    assert_not scraper.exhausted?
  end

  test "exhausted? is true when crashed" do
    scraper = BrowserScraper.new
    scraper.instance_variable_set(:@crashed, true)
    assert scraper.exhausted?
  end

  test "exhausted? is true when fetch_count reaches MAX_FETCHES_BEFORE_RECYCLE" do
    scraper = BrowserScraper.new
    scraper.instance_variable_set(:@fetch_count, BrowserScraper::MAX_FETCHES_BEFORE_RECYCLE)
    assert scraper.exhausted?
  end

  test "exhausted? is true when started_at exceeds MAX_AGE_BEFORE_RECYCLE" do
    scraper = BrowserScraper.new
    scraper.instance_variable_set(:@started_at, Time.current - BrowserScraper::MAX_AGE_BEFORE_RECYCLE - 1.second)
    assert scraper.exhausted?
  end

  test "crashed? reflects @crashed" do
    scraper = BrowserScraper.new
    scraper.instance_variable_set(:@crashed, true)
    assert scraper.crashed?
  end

  test "reset is a no-op when @browser is nil" do
    scraper = BrowserScraper.new
    assert_nil scraper.reset
  end

  test "reset calls @browser.reset and @browser.network.clear when browser is alive" do
    scraper = BrowserScraper.new
    mock_browser = MockBrowser.new
    scraper.instance_variable_set(:@browser, mock_browser)
    scraper.reset

    assert mock_browser.reset_called
    assert mock_browser.network.clear_called
  end

  test "reset sets @crashed to true and returns false on Ferrum::DeadBrowserError" do
    scraper = BrowserScraper.new
    mock_browser = MockBrowser.new
    mock_browser.define_singleton_method(:reset) { raise Ferrum::DeadBrowserError }

    scraper.instance_variable_set(:@browser, mock_browser)

    result = scraper.reset

    assert_equal false, result
    assert scraper.crashed?
  end
end

