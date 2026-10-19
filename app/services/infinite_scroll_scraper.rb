# Scraper for infinite scroll pages
#
# Uses BrowserScraper to handle pages that load content dynamically via
# infinite scroll or lazy loading. Scrolls the page until no new content
# loads, then extracts articles from the fully loaded page.
#
# Usage:
#   scraper = InfiniteScrollScraper.new(url: "https://example.com/blog")
#   result = scraper.scrape
#   # result[:html] => fully loaded HTML
#   # result[:articles] => extracted article data
#   # result[:scroll_count] => number of scrolls performed
#
# With custom options:
#   scraper = InfiniteScrollScraper.new(
#     url: "https://example.com/blog",
#     max_scrolls: 20,
#     scroll_wait: 1.5
#   )
#
class InfiniteScrollScraper
  class ScrapingError < StandardError; end

  # Default scraping configuration
  DEFAULT_OPTIONS = {
    max_scrolls: 10,
    scroll_wait: 2.0,
    scroll_distance: 1000,
    no_new_content_threshold: 3,
    extract_articles: true
  }.freeze

  attr_reader :url, :options, :result

  def initialize(url:, **options)
    @url = url
    @options = DEFAULT_OPTIONS.merge(options)
    @result = nil
  end

  # Scrapes the page with infinite scroll handling
  #
  # @return [Hash] Result with :html, :final_url, :scroll_count, and optionally :articles
  def scrape
    Rails.logger.info("[InfiniteScrollScraper] Starting scrape: #{@url}")

    BrowserScraper::Pool.with_scraper do |scraper|
      fetch_result = scraper.fetch_with_scroll(
        @url,
        max_scrolls: @options[:max_scrolls],
        scroll_wait: @options[:scroll_wait],
        scroll_distance: @options[:scroll_distance],
        no_new_content_threshold: @options[:no_new_content_threshold]
      )

      @result = {
        html: fetch_result[:content],
        final_url: fetch_result[:final_url],
        scroll_count: fetch_result[:scroll_count],
        fetched_at: Time.current
      }
    end

    # Optionally extract articles from the loaded content
    if @options[:extract_articles]
      @result[:articles] = extract_articles
    end

    Rails.logger.info("[InfiniteScrollScraper] Scrape complete: #{@result[:html].length} bytes, #{@result[:scroll_count]} scrolls")

    @result
  rescue BrowserScraper::BrowserError => e
    Rails.logger.error("[InfiniteScrollScraper] Browser error: #{e.message}")
    raise ScrapingError, "Browser error: #{e.message}"
  rescue StandardError => e
    Rails.logger.error("[InfiniteScrollScraper] Unexpected error: #{e.class.name} - #{e.message}")
    raise ScrapingError, "Scraping failed: #{e.message}"
  end

  # Extracts articles from the scraped HTML
  #
  # Uses the same extraction logic as WebProcessor for consistency.
  #
  # @return [Array<Hash>] Array of article data
  def extract_articles
    return [] unless @result && @result[:html]

    html = Nokogiri::HTML(@result[:html])
    results = WebProcessor.extract_articles_from_archive(html, @result[:final_url])
    articles = results.fetch(:articles, [])

    Rails.logger.info("[InfiniteScrollScraper] Extracted #{articles.length} articles")
    articles
  end

  # Scrapes and yields each page of articles
  #
  # Similar interface to PaginatedArchiveScraper for compatibility.
  # Unlike traditional pagination, this scrapes once with infinite scroll
  # but can be used with the same caller patterns.
  #
  # @yield [page_number, page_url, html, articles_data]
  # @yieldparam page_number [Integer] Always 1 for infinite scroll
  # @yieldparam page_url [String] The final URL
  # @yieldparam html [Nokogiri::HTML::Document] Parsed HTML document
  # @yieldparam articles_data [Array<Hash>] Extracted article data
  def each_page
    result = scrape

    html = Nokogiri::HTML(result[:html])
    articles = result[:articles] || extract_articles

    yield 1, result[:final_url], html, articles
  end

  # Whether the scrape completed successfully
  #
  # @return [Boolean]
  def completed?
    @result.present?
  end
end
