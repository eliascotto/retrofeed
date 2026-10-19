# Web fetcher abstraction that can use either live HTTP requests, mock fixture data,
# or browser-based fetching for JavaScript-rendered content.
#
# Usage:
#   result = WebFetcher.fetch("https://example.com/page")
#   result[:content]   # => HTML content
#   result[:final_url] # => final URL after any redirects
#
#   head = WebFetcher.head("https://example.com/page")
#   head[:status]     # => HTTP status code
#   head[:headers]    # => response headers
#   head[:final_url]  # => final URL after any redirects
#
# Browser-based fetching (for JavaScript-rendered pages):
#   result = WebFetcher.browser_fetch("https://example.com/spa")
#   result[:content]   # => Fully rendered HTML after JavaScript execution
#
# With infinite scroll:
#   result = WebFetcher.browser_fetch_with_scroll("https://example.com/infinite", max_scrolls: 10)
#
# In development, set MOCK_WEB_DATA=true to use fixture data instead of real HTTP requests.
# Fixture data is loaded from test/fixtures/ based on domain mapping in mock_mapping.yml.
#
module WebFetcher
  class FetchError < StandardError
    attr_reader :http_status, :headers, :content_type, :url, :http_method

    def initialize(message = nil, http_status: nil, headers: nil, content_type: nil, url: nil, http_method: "GET")
      @http_status = http_status
      @headers = headers
      @content_type = content_type
      @url = url
      @http_method = http_method
      super(message)
    end
  end

  class FixtureNotFoundError < FetchError; end

  # Fetches HTML content from a URL using HTTP
  #
  # HTTParty automatically follows redirects. The final URL after any redirects
  # is included in the return value so callers can use the canonical URL.
  #
  # @param url [String] The URL to fetch
  # @return [Hash] Hash with :content (String) and :final_url (String)
  # @raise [FetchError] If the fetch fails
  def self.fetch(url, no_mock: false)
    fetcher(no_mock: no_mock).fetch(url)
  end

  # Performs a HEAD request to a URL (robots-aware)
  # Useful for fast probing of candidate pages without downloading full content
  #
  # HTTParty automatically follows redirects. The final URL after any redirects
  # is included in the return value.
  #
  # @param url [String] The URL to probe
  # @return [Hash] Hash with :status (Integer), :headers (Hash), and :final_url (String)
  # @raise [FetchError] If the request fails
  def self.head(url)
    fetcher.head(url)
  end

  # Fetches HTML content using a headless browser
  #
  # Use this for pages that require JavaScript execution or have dynamic content.
  # More resource-intensive than HTTP fetching but handles JavaScript-rendered pages.
  #
  # @param url [String] The URL to fetch
  # @return [Hash] Hash with :content (String) and :final_url (String)
  # @raise [FetchError] If the fetch fails
  def self.browser_fetch(url)
    WebFetcher::Browser.fetch(url)
  end

  # Fetches HTML content using a headless browser with infinite scroll support
  #
  # Scrolls the page to load dynamically loaded content. Useful for pages
  # with infinite scroll or lazy-loaded content.
  #
  # @param url [String] The URL to fetch
  # @param max_scrolls [Integer] Maximum number of scroll actions (default: 10)
  # @param scroll_wait [Float] Seconds to wait after each scroll (default: 2.0)
  # @param scroll_distance [Integer] Pixels to scroll each time (default: 1000)
  # @return [Hash] Hash with :content, :final_url, and :scroll_count
  # @raise [FetchError] If the fetch fails
  def self.browser_fetch_with_scroll(url, max_scrolls: 10, scroll_wait: 2.0, scroll_distance: 1000)
    WebFetcher::Browser.fetch_with_scroll(
      url,
      max_scrolls: max_scrolls,
      scroll_wait: scroll_wait,
      scroll_distance: scroll_distance
    )
  end

  # Performs a HEAD-like request using the browser
  #
  # Since browsers don't do traditional HEAD requests, this is less efficient
  # than HTTP HEAD but works for JavaScript-rendered pages.
  #
  # @param url [String] The URL to probe
  # @return [Hash] Hash with :status (Integer), :headers (Hash), and :final_url (String)
  # @raise [FetchError] If the request fails
  def self.browser_head(url)
    WebFetcher::Browser.head(url)
  end

  # Returns true if browser mode is enabled globally
  #
  # When enabled, all fetches use the browser fetcher instead of HTTP.
  # Set USE_BROWSER_FETCHER=true to enable globally.
  def self.browser_mode?
    ENV["USE_BROWSER_FETCHER"] == "true"
  end

  # Returns true if mock mode is enabled
  # Works in development, or test environment when E2E_MOCK_DATA is set
  def self.mock_mode?
    return true if ENV["MOCK_WEB_DATA"] == "true" && Rails.env.development?
    return true if ENV["E2E_MOCK_DATA"] == "true" && Rails.env.test?
    false
  end

  # Returns the appropriate fetcher implementation
  #
  # Priority: Mock mode > Browser mode > Live HTTP
  def self.fetcher(no_mock: false)
    if mock_mode? && !no_mock
      WebFetcher::Mock
    elsif browser_mode?
      WebFetcher::Browser
    else
      WebFetcher::Live
    end
  end
end

require_relative "web_fetcher/live"
require_relative "web_fetcher/mock"
require_relative "web_fetcher/browser"
