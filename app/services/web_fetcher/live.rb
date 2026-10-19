# Live HTTP fetcher using HTTParty
#
# This is the default fetcher that makes real HTTP requests.
#
module WebFetcher
  module Live
    # Fetches HTML content from a URL using HTTParty
    #
    # HTTParty automatically follows redirects. We track the final URL after
    # any redirects so callers can use the canonical URL for validation.
    #
    # @param url [String] The URL to fetch
    # @return [Hash] Hash with :content (String) and :final_url (String)
    # @raise [WebFetcher::FetchError] If the fetch fails
    def self.fetch(url)
      Rails.logger.info("[WebFetcher::Live] Fetching: #{url}")

      enforce_robots_if_needed(url)

      response = HTTParty.get(url)

      # Extract HTTP context from the response
      status = response.code.to_i
      headers = response.headers.to_h
      content_type = headers["content-type"] || headers["Content-Type"]

      # Track final URL after any redirects (HTTParty follows redirects automatically)
      final_url = response.request.last_uri.to_s

      # Raise an error if the response is not successful
      unless (200..299).cover?(status)
        Rails.logger.error("[WebFetcher::Live] Non-success response (#{status}) for #{url}")
        raise WebFetcher::FetchError.new(
          "HTTP #{status} while fetching #{url}",
          http_status: status,
          headers: headers,
          content_type: content_type,
          url: url,
          http_method: "GET"
        )
      end

      if final_url != url
        Rails.logger.info("[WebFetcher::Live] Followed redirect: #{url} -> #{final_url}")
      end
      Rails.logger.info("[WebFetcher::Live] Successfully fetched #{response.body.length} bytes")

      { content: response.body, final_url: final_url }
    rescue HTTParty::Error, SocketError, Timeout::Error => e
      Rails.logger.error("[WebFetcher::Live] Failed to fetch #{url}: #{e.class.name} - #{e.message}")
      raise WebFetcher::FetchError.new("Failed to fetch URL: #{e.message}", url: url, http_method: "GET")
    rescue Addressable::URI::InvalidURIError => e
      Rails.logger.error("[WebFetcher::Live] Invalid URL #{url}: #{e.message}")
      raise WebFetcher::FetchError.new("Failed to fetch URL: #{e.message}", url: url, http_method: "GET")
    rescue WebFetcher::FetchError
      raise
    rescue StandardError => e
      Rails.logger.error("[WebFetcher::Live] Unexpected error fetching #{url}: #{e.message}")
      raise WebFetcher::FetchError.new("Failed to fetch URL: #{e.message}", url: url, http_method: "GET")
    end

    # Performs a HEAD request to a URL (robots-aware)
    # Returns status, headers, and final URL without downloading full content
    #
    # HTTParty automatically follows redirects. We track the final URL after
    # any redirects so callers can use the canonical URL.
    #
    # @param url [String] The URL to probe
    # @return [Hash] Hash with :status (Integer), :headers (Hash), and :final_url (String)
    # @raise [WebFetcher::FetchError] If the request fails
    def self.head(url)
      Rails.logger.info("[WebFetcher::Live] HEAD request: #{url}")

      enforce_robots_if_needed(url)

      response = HTTParty.head(url)

      status = response.code.to_i
      headers = response.headers.to_h

      # Track final URL after any redirects
      final_url = response.request.last_uri.to_s

      if final_url != url
        Rails.logger.info("[WebFetcher::Live] HEAD followed redirect: #{url} -> #{final_url}")
      end
      Rails.logger.info("[WebFetcher::Live] HEAD completed with status #{status}")

      { status: status, headers: headers, final_url: final_url }
    rescue HTTParty::Error, SocketError, Timeout::Error => e
      Rails.logger.error("[WebFetcher::Live] HEAD failed for #{url}: #{e.class.name} - #{e.message}")
      raise WebFetcher::FetchError.new("Failed HEAD request: #{e.message}", url: url, http_method: "HEAD")
    rescue Addressable::URI::InvalidURIError => e
      Rails.logger.error("[WebFetcher::Live] Invalid URL for HEAD #{url}: #{e.message}")
      raise WebFetcher::FetchError.new("Failed HEAD request: #{e.message}", url: url, http_method: "HEAD")
    rescue WebFetcher::FetchError
      raise
    rescue StandardError => e
      Rails.logger.error("[WebFetcher::Live] Unexpected error in HEAD #{url}: #{e.message}")
      raise WebFetcher::FetchError.new("Failed HEAD request: #{e.message}", url: url, http_method: "HEAD")
    end

    # Enforces robots.txt rules and crawl-delay for non-dev/test environments
    #
    # This is a critical safety measure that:
    # 1. Checks robots.txt to ensure the path is allowed (respects site owner's wishes)
    # 2. Enforces crawl-delay with random jitter (avoids predictable patterns)
    #
    # The crawl-delay enforcement includes random jitter (0-30% of base delay) to:
    # - Make request timing less predictable
    # - Avoid detection by anti-bot systems that look for regular intervals
    # - Make scraping behavior more human-like
    #
    # Skipped in development/test environments to allow faster testing.
    #
    # @param url [String] The URL being accessed
    # @return [void]
    # @raise [WebFetcher::FetchError] If robots.txt disallows the path
    def self.enforce_robots_if_needed(url)
      return if Rails.env.development? || Rails.env.test?

      robots = RobotsTxt.fetch_for(url)
      path = Addressable::URI.parse(url).path.presence || "/"

      # Check if robots.txt disallows this path
      # This respects the site owner's robots.txt rules
      if robots && !robots.allowed?(path)
        raise WebFetcher::FetchError, "robots.txt disallows fetching: #{url}"
      end

      # Enforce crawl-delay with random jitter to avoid predictable patterns
      # The jitter helps avoid AI trap detection systems
      RobotsTxt.enforce_crawl_delay_with(robots, url, user_agent: RobotsTxt.default_user_agent)
    end
  end
end
