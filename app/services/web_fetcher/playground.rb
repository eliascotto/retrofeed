# Playground HTTP fetcher that wraps WebFetcher with fixture caching
#
# This fetcher checks the playground fixture cache first, falling back to
# live fetching (bypassing MOCK_WEB_DATA so missing fixtures are downloaded).
# Uses browser fetcher if USE_BROWSER_FETCHER is enabled.
# Fetched pages are automatically cached for future use.
#
# Returns both :content (standard format) and :html (backward compatibility)
# keys in the result hash.
#
# Usage:
#   result = WebFetcher::Playground.fetch("https://example.com/blog")
#   result[:content]      # => "<html>..." (standard format)
#   result[:html]         # => "<html>..." (backward compatibility)
#   result[:source]       # => :fixture or :live
#   result[:fetcher_type] # => "live", "browser", or "mock"
#
module WebFetcher
  module Playground
    class << self
      # Fetches HTML content, checking fixtures first then falling back to WebFetcher
      #
      # Appends fetch metadata to Thread.current[:playground_fetch_log] when set,
      # allowing callers to track all pages fetched during a detection run.
      #
      # @param url [String] The URL to fetch
      # @return [Hash] Result with :content, :html, :source, :fetched_at, :fetcher_type
      def fetch(url)
        Rails.logger.info("[WebFetcher::Playground] Fetching: #{url}")

        fixture_path = ::Playground::FixtureCache.find_fixture(url)

        result = if fixture_path
          metadata = ::Playground::FixtureCache.load_metadata(url) || {}
          html = File.binread(fixture_path)

          Rails.logger.info("[WebFetcher::Playground] Loaded from fixture (#{html.bytesize} bytes)")

          {
            content: html,
            html: html,
            source: :fixture,
            fetched_at: metadata[:fetched_at],
            http_status: metadata[:http_status] || 200,
            final_url: metadata[:final_url] || url,
            fixture_path: fixture_path,
            fetcher_type: metadata[:fetcher_type] || "live"
          }
        else
          fetch_and_cache(url)
        end

        if (log = Thread.current[:playground_fetch_log])
          log << {
            url: result[:final_url] || url,
            source: result[:source],
            size: result[:content]&.bytesize,
            fetched_at: result[:fetched_at],
            fetcher_type: result[:fetcher_type]
          }
        end

        result
      end

      # Fetches HTML content and caches the result
      #
      # Always fetches live data (bypassing mock mode) so the playground can download
      # missing fixtures. Uses browser fetcher if USE_BROWSER_FETCHER is enabled.
      #
      # @param url [String] The URL to fetch
      # @return [Hash] Result with :content, :html, :source, :fetched_at, :fetcher_type
      def fetch_and_cache(url)
        Rails.logger.info("[WebFetcher::Playground] Fetching live data for caching: #{url}")

        # Bypass mock mode - always fetch live data so we can cache it
        # Use browser fetcher if enabled, otherwise use live HTTP
        fetcher_type = WebFetcher.browser_mode? ? "browser" : "live"
        result = if WebFetcher.browser_mode?
          WebFetcher::Browser.fetch(url)
        else
          WebFetcher::Live.fetch(url)
        end

        html = result[:content]
        final_url = result[:final_url]

        if Thread.current[:playground_skip_fixture]
          Rails.logger.info("[WebFetcher::Playground] Skip fixture mode - not caching #{html.bytesize} bytes")
        else
          ::Playground::FixtureCache.save_fixture(final_url, html, {
            http_status: 200,
            original_url: url,
            final_url: final_url,
            fetcher_type: fetcher_type,
            scroll_count: result[:scroll_count]
          }.compact)

          Rails.logger.info("[WebFetcher::Playground] Cached #{html.bytesize} bytes via #{fetcher_type} (final: #{final_url})")
        end

        {
          content: html,
          html: html,
          source: :live,
          fetched_at: Time.current.iso8601,
          http_status: 200,
          final_url: final_url,
          fixture_path: Thread.current[:playground_skip_fixture] ? nil : ::Playground::FixtureCache.fixture_path(final_url),
          fetcher_type: fetcher_type,
          scroll_count: result[:scroll_count]
        }
      rescue WebFetcher::FetchError
        raise
      rescue StandardError => e
        Rails.logger.error("[WebFetcher::Playground] Failed to fetch #{url}: #{e.class.name} - #{e.message}")
        raise WebFetcher::FetchError.new("Failed to fetch URL: #{e.message}", url: url, http_method: "GET")
      end

      # Returns just the HTML content (for compatibility with WebFetcher interface)
      #
      # @param url [String] The URL to fetch
      # @return [String] The HTML content
      def fetch_html(url)
        result = fetch(url)
        result[:content]
      end

      # Performs a HEAD request, checking fixture cache first
      #
      # @param url [String] The URL to probe
      # @return [Hash] Hash with :status, :headers, and :final_url
      def head(url)
        Rails.logger.info("[WebFetcher::Playground] HEAD request: #{url}")

        # Check if we have a fixture - return 200 if so
        fixture_path = ::Playground::FixtureCache.find_fixture(url)
        if fixture_path
          metadata = ::Playground::FixtureCache.load_metadata(url) || {}
          final_url = metadata[:final_url] || url
          Rails.logger.info("[WebFetcher::Playground] HEAD returning 200 (fixture exists, final: #{final_url})")
          return { status: 200, headers: { "content-type" => "text/html" }, final_url: final_url }
        end

        # Use standard WebFetcher.head (respects env vars)
        WebFetcher.head(url)
      rescue WebFetcher::FetchError
        raise
      rescue StandardError => e
        Rails.logger.error("[WebFetcher::Playground] HEAD failed for #{url}: #{e.message}")
        raise WebFetcher::FetchError.new("Failed to probe URL: #{e.message}", url: url, http_method: "HEAD")
      end

      # Refreshes a fixture by forcing a new fetch
      #
      # @param url [String] The URL to refresh
      # @return [Hash] Result with :content, :html, :source, :fetched_at, :fetcher_type
      def refresh(url)
        ::Playground::FixtureCache.clear_fixture(url)
        fetch_and_cache(url)
      end

      # Fetches HTML content with infinite scroll support
      #
      # Checks fixture cache first (using scroll-specific cache key), then falls back
      # to browser-based fetching with scroll handling.
      #
      # @param url [String] The URL to fetch
      # @param max_scrolls [Integer] Maximum number of scroll actions (default: 5)
      # @param scroll_wait [Float] Seconds to wait after each scroll (default: 1.0)
      # @param scroll_distance [Integer] Pixels to scroll each time (default: 1000)
      # @return [Hash] Result with :content, :html, :source, :fetched_at, :fetcher_type, :scroll_count
      def fetch_with_scroll(url, max_scrolls: 5, scroll_wait: 1.0, scroll_distance: 1000)
        Rails.logger.info("[WebFetcher::Playground] Fetching with scroll: #{url} (max: #{max_scrolls})")

        # For cached fixtures, we just return the cached content
        # The scroll would have already been performed when the fixture was created
        fixture_path = ::Playground::FixtureCache.find_fixture(url)

        if fixture_path
          metadata = ::Playground::FixtureCache.load_metadata(url) || {}
          html = File.binread(fixture_path)

          Rails.logger.info("[WebFetcher::Playground] Loaded from fixture with scroll data (#{html.bytesize} bytes)")

          return {
            content: html,
            html: html,
            source: :fixture,
            fetched_at: metadata[:fetched_at],
            http_status: metadata[:http_status] || 200,
            final_url: metadata[:final_url] || url,
            fixture_path: fixture_path,
            fetcher_type: metadata[:fetcher_type] || "browser",
            scroll_count: metadata[:scroll_count] || 0
          }
        end

        # No fixture - fetch with browser and scroll
        fetch_with_scroll_and_cache(url, max_scrolls: max_scrolls, scroll_wait: scroll_wait, scroll_distance: scroll_distance)
      end

      # Fetches HTML with infinite scroll using browser and caches the result
      #
      # @param url [String] The URL to fetch
      # @param max_scrolls [Integer] Maximum number of scroll actions
      # @param scroll_wait [Float] Seconds to wait after each scroll
      # @param scroll_distance [Integer] Pixels to scroll each time
      # @return [Hash] Result with :content, :html, :source, :fetched_at, :fetcher_type, :scroll_count
      def fetch_with_scroll_and_cache(url, max_scrolls:, scroll_wait:, scroll_distance:)
        Rails.logger.info("[WebFetcher::Playground] Fetching with scroll via browser: #{url}")

        # Use browser-based fetching with scroll support
        result = WebFetcher.browser_fetch_with_scroll(
          url,
          max_scrolls: max_scrolls,
          scroll_wait: scroll_wait,
          scroll_distance: scroll_distance
        )

        html = result[:content]
        final_url = result[:final_url]
        scroll_count = result[:scroll_count] || 0

        if Thread.current[:playground_skip_fixture]
          Rails.logger.info("[WebFetcher::Playground] Skip fixture mode - not caching #{html.bytesize} bytes with #{scroll_count} scrolls")
        else
          ::Playground::FixtureCache.save_fixture(final_url, html, {
            http_status: 200,
            original_url: url,
            final_url: final_url,
            fetcher_type: "browser",
            scroll_count: scroll_count,
            max_scrolls: max_scrolls
          }.compact)

          Rails.logger.info("[WebFetcher::Playground] Cached #{html.bytesize} bytes with #{scroll_count} scrolls")
        end

        {
          content: html,
          html: html,
          source: :live,
          fetched_at: Time.current.iso8601,
          http_status: 200,
          final_url: final_url,
          fixture_path: Thread.current[:playground_skip_fixture] ? nil : ::Playground::FixtureCache.fixture_path(final_url),
          fetcher_type: "browser",
          scroll_count: scroll_count
        }
      rescue WebFetcher::FetchError
        raise
      rescue StandardError => e
        Rails.logger.error("[WebFetcher::Playground] Failed to fetch with scroll #{url}: #{e.class.name} - #{e.message}")
        raise WebFetcher::FetchError.new("Failed to fetch URL with scroll: #{e.message}", url: url, http_method: "GET")
      end
    end
  end
end
