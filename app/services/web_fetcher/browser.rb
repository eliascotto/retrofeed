# Browser-based HTTP fetcher using Ferrum
#
# This fetcher uses a headless Chrome browser to render JavaScript content.
# Use this for pages that require JavaScript execution or have dynamic content.
#
# Usage:
#   result = WebFetcher::Browser.fetch("https://example.com")
#   result[:content]   # => rendered HTML string
#   result[:final_url] # => final URL after any redirects
#
# For infinite scroll pages:
#   result = WebFetcher::Browser.fetch_with_scroll("https://example.com", max_scrolls: 10)
#
module WebFetcher
  module Browser
    class << self
      # Fetches HTML content from a URL using a headless browser
      #
      # The browser renders JavaScript and waits for the page to load.
      # Returns the fully rendered HTML after JavaScript execution.
      #
      # @param url [String] The URL to fetch
      # @return [Hash] Hash with :content (String) and :final_url (String)
      # @raise [WebFetcher::FetchError] If the fetch fails
      def fetch(url)
        Rails.logger.info("[WebFetcher::Browser] Fetching: #{url}")

        enforce_robots_if_needed(url)

        BrowserScraper::Pool.with_scraper do |scraper|
          result = scraper.fetch(url)

          Rails.logger.info("[WebFetcher::Browser] Successfully fetched #{result[:content].length} bytes")
          result
        end
      rescue BrowserScraper::BrowserCrashedError => e
        Rails.logger.error("[WebFetcher::Browser] Browser crashed for #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser crashed: #{e.message}", url: url, http_method: "GET")
      rescue BrowserScraper::BrowserStartError => e
        Rails.logger.error("[WebFetcher::Browser] Failed to start browser for #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser failed to start: #{e.message}", url: url, http_method: "GET")
      rescue BrowserScraper::BrowserTimeoutError => e
        Rails.logger.error("[WebFetcher::Browser] Browser timeout for #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser timeout: #{e.message}", url: url, http_method: "GET")
      rescue BrowserScraper::BrowserError => e
        Rails.logger.error("[WebFetcher::Browser] Browser error for #{url}: #{e.class.name} - #{e.message}")
        raise WebFetcher::FetchError.new("Browser failed to fetch URL: #{e.message}", url: url, http_method: "GET")
      rescue Ferrum::TimeoutError => e
        Rails.logger.error("[WebFetcher::Browser] Timeout for #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser timeout fetching URL: #{e.message}", url: url, http_method: "GET")
      rescue Ferrum::Error => e
        Rails.logger.error("[WebFetcher::Browser] Ferrum error for #{url}: #{e.class.name} - #{e.message}")
        raise WebFetcher::FetchError.new("Browser error: #{e.message}", url: url, http_method: "GET")
      rescue WebFetcher::FetchError
        raise
      rescue StandardError => e
        Rails.logger.error("[WebFetcher::Browser] Unexpected error fetching #{url}: #{e.class.name} - #{e.message}")
        raise WebFetcher::FetchError.new("Failed to fetch URL: #{e.message}", url: url, http_method: "GET")
      end

      # Fetches HTML content with infinite scroll support
      #
      # Scrolls the page to load dynamically loaded content.
      # Useful for pages with infinite scroll or lazy-loaded content.
      #
      # @param url [String] The URL to fetch
      # @param max_scrolls [Integer] Maximum number of scroll actions (default: 10)
      # @param scroll_wait [Float] Seconds to wait after each scroll (default: 2.0)
      # @param scroll_distance [Integer] Pixels to scroll each time (default: 1000)
      # @return [Hash] Hash with :content, :final_url, and :scroll_count
      # @raise [WebFetcher::FetchError] If the fetch fails
      def fetch_with_scroll(url, max_scrolls: 10, scroll_wait: 2.0, scroll_distance: 1000)
        Rails.logger.info("[WebFetcher::Browser] Fetching with scroll: #{url} (max: #{max_scrolls})")

        enforce_robots_if_needed(url)

        BrowserScraper::Pool.with_scraper do |scraper|
          result = scraper.fetch_with_scroll(
            url,
            max_scrolls: max_scrolls,
            scroll_wait: scroll_wait,
            scroll_distance: scroll_distance
          )

          Rails.logger.info("[WebFetcher::Browser] Successfully fetched #{result[:content].length} bytes after #{result[:scroll_count]} scrolls")
          result
        end
      rescue BrowserScraper::BrowserCrashedError => e
        Rails.logger.error("[WebFetcher::Browser] Browser crashed during scroll for #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser crashed: #{e.message}", url: url, http_method: "GET")
      rescue BrowserScraper::BrowserStartError => e
        Rails.logger.error("[WebFetcher::Browser] Failed to start browser for scroll fetch #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser failed to start: #{e.message}", url: url, http_method: "GET")
      rescue BrowserScraper::BrowserTimeoutError => e
        Rails.logger.error("[WebFetcher::Browser] Browser timeout for scroll fetch #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser timeout: #{e.message}", url: url, http_method: "GET")
      rescue BrowserScraper::BrowserError => e
        Rails.logger.error("[WebFetcher::Browser] Browser error for #{url}: #{e.class.name} - #{e.message}")
        raise WebFetcher::FetchError.new("Browser failed to fetch URL: #{e.message}", url: url, http_method: "GET")
      rescue Ferrum::TimeoutError => e
        Rails.logger.error("[WebFetcher::Browser] Timeout for #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser timeout fetching URL: #{e.message}", url: url, http_method: "GET")
      rescue Ferrum::Error => e
        Rails.logger.error("[WebFetcher::Browser] Ferrum error for #{url}: #{e.class.name} - #{e.message}")
        raise WebFetcher::FetchError.new("Browser error: #{e.message}", url: url, http_method: "GET")
      rescue WebFetcher::FetchError
        raise
      rescue StandardError => e
        Rails.logger.error("[WebFetcher::Browser] Unexpected error fetching #{url}: #{e.class.name} - #{e.message}")
        raise WebFetcher::FetchError.new("Failed to fetch URL: #{e.message}", url: url, http_method: "GET")
      end

      # Performs a HEAD-like request using the browser
      #
      # Since browsers don't do traditional HEAD requests, this navigates to the page
      # and extracts status information. Less efficient than HTTP HEAD but works
      # for JavaScript-rendered pages.
      #
      # @param url [String] The URL to probe
      # @return [Hash] Hash with :status (Integer), :headers (Hash), and :final_url (String)
      # @raise [WebFetcher::FetchError] If the request fails
      def head(url)
        Rails.logger.info("[WebFetcher::Browser] HEAD request (via full fetch): #{url}")

        enforce_robots_if_needed(url)

        BrowserScraper::Pool.with_scraper do |scraper|
          scraper.with_browser do |browser|
            scraper.navigate_to(url)

            final_url = browser.current_url
            # Browser doesn't give us HTTP status directly, assume 200 if page loaded
            status = 200
            headers = { "content-type" => "text/html" }

            Rails.logger.info("[WebFetcher::Browser] HEAD completed for #{final_url}")
            { status: status, headers: headers, final_url: final_url }
          end
        end
      rescue BrowserScraper::BrowserCrashedError => e
        Rails.logger.error("[WebFetcher::Browser] Browser crashed for HEAD #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser crashed: #{e.message}", url: url, http_method: "HEAD")
      rescue BrowserScraper::BrowserStartError => e
        Rails.logger.error("[WebFetcher::Browser] Failed to start browser for HEAD #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser failed to start: #{e.message}", url: url, http_method: "HEAD")
      rescue BrowserScraper::BrowserError => e
        Rails.logger.error("[WebFetcher::Browser] Browser error for HEAD #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser failed HEAD request: #{e.message}", url: url, http_method: "HEAD")
      rescue Ferrum::StatusError => e
        # Ferrum raises StatusError for non-2xx responses
        Rails.logger.error("[WebFetcher::Browser] Status error for HEAD #{url}: #{e.message}")
        raise WebFetcher::FetchError.new(
          "HTTP error while fetching #{url}",
          url: url,
          http_method: "HEAD"
        )
      rescue Ferrum::Error => e
        Rails.logger.error("[WebFetcher::Browser] Ferrum error for HEAD #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Browser error: #{e.message}", url: url, http_method: "HEAD")
      rescue WebFetcher::FetchError
        raise
      rescue StandardError => e
        Rails.logger.error("[WebFetcher::Browser] Unexpected error in HEAD #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Failed HEAD request: #{e.message}", url: url, http_method: "HEAD")
      end

      private

      # Enforces robots.txt rules and crawl-delay for non-dev/test environments
      #
      # Same safety measures as WebFetcher::Live to respect site owner's wishes.
      #
      # @param url [String] The URL being accessed
      # @return [void]
      # @raise [WebFetcher::FetchError] If robots.txt disallows the path
      def enforce_robots_if_needed(url)
        return if Rails.env.development? || Rails.env.test?

        robots = RobotsTxt.fetch_for(url)
        path = Addressable::URI.parse(url).path.presence || "/"

        if robots && !robots.allowed?(path)
          raise WebFetcher::FetchError, "robots.txt disallows fetching: #{url}"
        end

        RobotsTxt.enforce_crawl_delay_with(robots, url, user_agent: RobotsTxt.default_user_agent)
      end
    end
  end
end
