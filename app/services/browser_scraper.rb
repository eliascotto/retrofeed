# Base service for browser-based scraping using Ferrum
#
# Manages browser lifecycle and provides common scraping operations.
# Designed for JavaScript-rendered content and infinite scroll pages.
#
# Usage:
#   scraper = BrowserScraper.new
#   result = scraper.fetch("https://example.com")
#   # result[:content] => HTML string
#   # result[:final_url] => final URL after any redirects
#
# For infinite scroll:
#   scraper = BrowserScraper.new
#   result = scraper.fetch_with_scroll("https://example.com", max_scrolls: 10)
#
# Important: Always call #quit when done, or use #with_browser block:
#   scraper.with_browser do |browser|
#     # operations here
#   end # browser automatically cleaned up
#
# Error Handling:
#   - Browser crashes are detected and cleaned up automatically
#   - Timeouts are handled gracefully (partial content may be returned)
#   - Memory cleanup is ensured via ensure blocks
#   - All errors are wrapped in BrowserError subclasses
#
class BrowserScraper
  # Error classes for browser operations
  class BrowserError < StandardError; end
  class BrowserStartError < BrowserError; end
  class BrowserCrashedError < BrowserError; end
  class BrowserTimeoutError < BrowserError; end
  class NavigationError < BrowserError; end
  class TimeoutError < BrowserError; end

  PRIVATE_RANGES = [
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10")
  ].freeze


  # Default configuration for headless Chrome in Docker
  DEFAULT_OPTIONS = {
    headless: true,
    timeout: 10,
    process_timeout: 30,
    browser_options: {
      "no-sandbox" => nil,
      "disable-dev-shm-usage" => nil,
      "disable-gpu" => nil,
      "disable-software-rasterizer" => nil,
      "disable-extensions" => nil,
      "disable-background-networking" => nil,
      "disable-sync" => nil,
      "disable-plugins" => nil,
      "disable-translate" => nil,
      "metrics-recording-only" => nil,
      "mute-audio" => nil,
      "no-first-run" => nil
    }
  }.freeze

  # Default scroll configuration
  DEFAULT_SCROLL_OPTIONS = {
    max_scrolls: 10,
    scroll_wait: 2.0,
    scroll_distance: 1000,
    no_new_content_threshold: 3
  }.freeze

  # Recycling configuration
  MAX_FETCHES_BEFORE_RECYCLE = 50
  MAX_AGE_BEFORE_RECYCLE = 30.minutes

  # Maximum retries for browser operations
  MAX_RETRIES = 2

  attr_reader :browser, :options

  def initialize(options = {})
    @options = DEFAULT_OPTIONS.deep_merge(options)
    @browser = nil
    @started = false
    @crashed = false
    @fetch_count = 0
    @started_at = nil

    # Use custom browser path if set via environment (for Docker)
    if ENV["BROWSER_PATH"].present?
      @options[:browser_path] = ENV["BROWSER_PATH"]
    end
  end

  # Starts the browser if not already running
  #
  # @return [Ferrum::Browser]
  # @raise [BrowserError] If browser fails to start
  def start
    return @browser if @started && @browser && !@crashed

    # Clean up crashed browser before restarting
    force_cleanup if @crashed

    Rails.logger.info("[BrowserScraper] Starting browser with options: #{@options.except(:browser_options)}")
    @browser = Ferrum::Browser.new(**@options)
    @browser.network.intercept
    @browser.on(:request) do |request|
      UrlUtils.safe_url_for_processing?(request.url) ? request.continue : request.abort
    end

    @started_at = Time.current
    @started = true
    @crashed = false
    @fetch_count = 0
    Rails.logger.info("[BrowserScraper] Browser started successfully (PID: #{@browser.process.pid rescue 'unknown'})")
    @browser
  rescue Ferrum::ProcessTimeoutError => e
    Rails.logger.error("[BrowserScraper] Browser process timeout: #{e.message}")
    force_cleanup
    raise BrowserStartError, "Browser process timed out: #{e.message}"
  rescue Ferrum::Error => e
    Rails.logger.error("[BrowserScraper] Failed to start browser: #{e.class.name} - #{e.message}")
    force_cleanup
    raise BrowserStartError, "Failed to start browser: #{e.message}"
  rescue Errno::ENOENT => e
    Rails.logger.error("[BrowserScraper] Browser executable not found: #{e.message}")
    raise BrowserStartError, "Browser executable not found. Ensure Chrome/Chromium is installed."
  end

  # Stops the browser and cleans up resources
  #
  # @return [void]
  def quit
    return unless @browser

    Rails.logger.info("[BrowserScraper] Stopping browser")
    begin
      @browser.quit
    rescue Ferrum::DeadBrowserError
      Rails.logger.warn("[BrowserScraper] Browser already dead during quit")
    rescue Ferrum::Error => e
      Rails.logger.warn("[BrowserScraper] Error during browser quit: #{e.message}")
    end

    @browser = nil
    @started = false
    @crashed = false
  end

  # Force cleanup of browser resources
  #
  # Used when browser has crashed or is in an unknown state.
  # More aggressive than quit - attempts to kill browser process.
  #
  # @return [void]
  def force_cleanup
    Rails.logger.info("[BrowserScraper] Force cleanup of browser resources")

    if @browser
      begin
        # Try to get the process and kill it
        if @browser.respond_to?(:process) && @browser.process
          pid = @browser.process.pid rescue nil
          if pid
            Rails.logger.info("[BrowserScraper] Killing browser process: #{pid}")
            Process.kill("KILL", pid) rescue nil
          end
        end
        @browser.quit rescue nil
      rescue StandardError => e
        Rails.logger.warn("[BrowserScraper] Error during force cleanup: #{e.message}")
      end
    end

    @browser = nil
    @started = false
    @crashed = false
  end

  # Checks if the browser has crashed
  #
  # @return [Boolean] true if browser has crashed
  def crashed?
    @crashed
  end

  # Checks if the browser has exhausted its resources:
  # - Browser is crashed
  # - Fetch count exceeds limit
  # - Max duration exceeded
  #
  # @return [Boolean] true if browser is crashed, fetch count exceeds limit, or max duration exceeded
  def exhausted?
    @crashed ||
      @fetch_count >= MAX_FETCHES_BEFORE_RECYCLE ||
      (@started_at && Time.current >= @started_at + MAX_AGE_BEFORE_RECYCLE)
  end

  # Resets the browser for reuse
  #
  # Clears browser state and network traffic to ensure a clean state for the next use.
  # Returns false if the browser is crashed or dead, true otherwise.
  #
  # @return [Boolean] true if reset was successful, false if browser is crashed or dead
  def reset
    return unless @browser

    @browser.reset
    @browser.network.clear(:traffic)
  rescue Ferrum::DeadBrowserError
    @crashed = true
    false
  rescue Ferrum::Error => e
    Rails.logger.warn("[BrowserScraper] Error during reset: #{e.message}")
    false
  end

  # Executes a block with browser, does not handle cleanup and quit
  #
  # @yield [Ferrum::Browser]
  # @return [Object] Result of the block
  # @raise [BrowserError] If browser crashes during block execution
  def with_browser
    start
    yield @browser
  rescue Ferrum::DeadBrowserError => e
    Rails.logger.error("[BrowserScraper] Browser died during operation: #{e.message}")
    @crashed = true
    raise BrowserCrashedError, "Browser crashed: #{e.message}"
  rescue Ferrum::ProcessTimeoutError => e
    Rails.logger.error("[BrowserScraper] Browser process timeout: #{e.message}")
    @crashed = true
    raise BrowserTimeoutError, "Browser process timeout: #{e.message}"
  end

  # Fetches a page and returns the rendered HTML
  #
  # @param url [String] The URL to fetch
  # @param wait_for_idle [Boolean] Wait for network idle before extracting HTML
  # @return [Hash] Hash with :content (String) and :final_url (String)
  # @raise [BrowserError] If navigation fails
  def fetch(url, wait_for_idle: true)
    Rails.logger.info("[BrowserScraper] Fetching: #{url}")

    with_browser do |browser|
      navigate_to(url, wait_for_idle: wait_for_idle)
      @fetch_count += 1
      extract_result
    end
  end

  # Fetches a page with infinite scroll support
  #
  # @param url [String] The URL to fetch
  # @param scroll_options [Hash] Scroll configuration options
  # @option scroll_options [Integer] :max_scrolls Maximum number of scroll actions
  # @option scroll_options [Float] :scroll_wait Seconds to wait after each scroll
  # @option scroll_options [Integer] :scroll_distance Pixels to scroll each time
  # @option scroll_options [Integer] :no_new_content_threshold Stop after this many scrolls with no new content
  # @return [Hash] Hash with :content (String), :final_url (String), and :scroll_count (Integer)
  def fetch_with_scroll(url, **scroll_options)
    Rails.logger.info("[BrowserScraper] Fetching with scroll: #{url}")

    options = DEFAULT_SCROLL_OPTIONS.merge(scroll_options)

    with_browser do |browser|
      navigate_to(url)
      scroll_count = perform_infinite_scroll(**options)
      @fetch_count += 1

      result = extract_result
      result[:scroll_count] = scroll_count
      result
    end
  end

  # Navigates to a URL
  #
  # @param url [String] The URL to navigate to
  # @param wait_for_idle [Boolean] Wait for network idle
  # @return [void]
  # @raise [NavigationError] If navigation fails
  # @raise [BrowserCrashedError] If browser crashes during navigation
  def navigate_to(url, wait_for_idle: true)
    start unless @started

    Rails.logger.debug("[BrowserScraper] Navigating to: #{url}")

    begin
      @browser.go_to(url)
    rescue Ferrum::StatusError => e
      # Non-2xx HTTP status
      Rails.logger.error("[BrowserScraper] HTTP error for #{url}: #{e.message}")
      raise NavigationError, "HTTP error navigating to #{url}: #{e.message}"
    rescue Ferrum::DeadBrowserError => e
      @crashed = true
      raise BrowserCrashedError, "Browser crashed during navigation: #{e.message}"
    end

    if wait_for_idle
      begin
        @browser.network.wait_for_idle(timeout: @options[:timeout])
      rescue Ferrum::TimeoutError => e
        Rails.logger.warn("[BrowserScraper] Timeout waiting for network idle: #{url} - #{e.message}")
        # Continue anyway, page may be partially loaded
      end
    end

    Rails.logger.debug("[BrowserScraper] Navigation complete, current URL: #{@browser.current_url}")
  rescue Ferrum::TimeoutError => e
    Rails.logger.warn("[BrowserScraper] Timeout waiting for page: #{url} - #{e.message}")
    # Continue anyway, page may be partially loaded
  rescue Ferrum::DeadBrowserError => e
    @crashed = true
    raise BrowserCrashedError, "Browser crashed: #{e.message}"
  rescue Ferrum::Error => e
    Rails.logger.error("[BrowserScraper] Navigation failed for #{url}: #{e.class.name} - #{e.message}")
    raise NavigationError, "Failed to navigate to #{url}: #{e.message}"
  end

  # Extracts the current page HTML and URL
  #
  # @return [Hash] Hash with :content (String) and :final_url (String)
  # @raise [BrowserError] If browser not started or extraction fails
  def extract_result
    raise BrowserError, "Browser not started" unless @browser

    begin
      content = @browser.body
      final_url = @browser.current_url
    rescue Ferrum::DeadBrowserError => e
      @crashed = true
      raise BrowserCrashedError, "Browser crashed during content extraction: #{e.message}"
    rescue Ferrum::Error => e
      raise BrowserError, "Failed to extract page content: #{e.message}"
    end

    if content.nil? || content.empty?
      Rails.logger.warn("[BrowserScraper] Extracted empty content from #{final_url}")
    else
      Rails.logger.info("[BrowserScraper] Extracted #{content.length} bytes from #{final_url}")
    end

    { content: content || "", final_url: final_url }
  end

  # Scrolls the page to trigger infinite scroll loading
  #
  # @param max_scrolls [Integer] Maximum number of scroll actions
  # @param scroll_wait [Float] Seconds to wait after each scroll
  # @param scroll_distance [Integer] Pixels to scroll each time
  # @param no_new_content_threshold [Integer] Stop after this many scrolls with no new content
  # @return [Integer] Number of scrolls performed
  # @raise [BrowserCrashedError] If browser crashes during scrolling
  def perform_infinite_scroll(max_scrolls:, scroll_wait:, scroll_distance:, no_new_content_threshold:)
    raise BrowserError, "Browser not started" unless @browser

    Rails.logger.info("[BrowserScraper] Starting infinite scroll (max: #{max_scrolls}, wait: #{scroll_wait}s)")

    scroll_count = 0
    no_new_content_count = 0
    last_height = get_scroll_height

    max_scrolls.times do |i|
      scroll_count = i + 1

      begin
        # Scroll down
        scroll_by(scroll_distance)
        sleep(scroll_wait)

        # Check if new content loaded
        new_height = get_scroll_height
      rescue Ferrum::DeadBrowserError => e
        @crashed = true
        Rails.logger.error("[BrowserScraper] Browser crashed during scroll #{scroll_count}: #{e.message}")
        raise BrowserCrashedError, "Browser crashed during scrolling: #{e.message}"
      rescue Ferrum::Error => e
        Rails.logger.warn("[BrowserScraper] Error during scroll #{scroll_count}: #{e.message}")
        # Try to continue, some errors are recoverable
        break
      end

      if new_height == last_height
        no_new_content_count += 1
        Rails.logger.debug("[BrowserScraper] Scroll #{scroll_count}: No new content (#{no_new_content_count}/#{no_new_content_threshold})")

        if no_new_content_count >= no_new_content_threshold
          Rails.logger.info("[BrowserScraper] Stopping scroll: no new content after #{no_new_content_threshold} attempts")
          break
        end
      else
        no_new_content_count = 0
        Rails.logger.debug("[BrowserScraper] Scroll #{scroll_count}: Height changed #{last_height} -> #{new_height}")
      end

      last_height = new_height
    end

    Rails.logger.info("[BrowserScraper] Infinite scroll complete: #{scroll_count} scrolls performed")
    scroll_count
  end

  # Scrolls the page by a specified distance
  #
  # @param distance [Integer] Pixels to scroll (positive = down)
  # @return [void]
  def scroll_by(distance)
    @browser.execute("window.scrollBy(0, #{distance})")
  end

  # Scrolls to the bottom of the page
  #
  # @return [void]
  def scroll_to_bottom
    @browser.execute("window.scrollTo(0, document.body.scrollHeight)")
  end

  # Gets the current scroll height of the document
  #
  # @return [Integer]
  def get_scroll_height
    @browser.evaluate("document.body.scrollHeight").to_i
  end

  # Waits for a CSS selector to appear
  #
  # @param selector [String] CSS selector
  # @param timeout [Integer] Timeout in seconds
  # @return [Ferrum::Node, nil]
  def wait_for_selector(selector, timeout: 10)
    @browser.at_css(selector, wait: timeout)
  rescue Ferrum::NodeNotFoundError
    nil
  end
end
