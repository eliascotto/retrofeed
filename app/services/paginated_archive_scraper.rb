# Iterates through paginated archive pages, fetching each and extracting articles
#
# This scraper safely navigates paginated archives by:
# 1. Finding next page links using multiple strategies (rel="next", pagination containers, link text)
# 2. Fetching pages via WebFetcher (which enforces robots.txt and crawl delays)
# 3. Extracting articles via WebProcessor
# 4. Only following same-origin links to avoid off-site navigation
#
# Safety features:
# - Only follows links from the same origin (prevents off-site navigation)
# - Uses WebFetcher which enforces robots.txt rules and crawl delays
# - Multiple pagination detection strategies to handle various blog formats
# - Stops when no next page is found (natural end detection)
#
# Note: This class does NOT implement trap detection - that's handled by
# PaginationGuard in the calling job (PaginateArchiveJob).
#
# Usage:
#   scraper = PaginatedArchiveScraper.new(start_url: "https://example.com/blog", origin: "https://example.com")
#   scraper.each_page do |page_number, page_url, html, articles_data|
#     # process page
#   end
#   scraper.completed?  # => true if reached end naturally
#
class PaginatedArchiveScraper
  # Pagination URL patterns for detection and page number extraction
  PAGINATION_URL_PATTERNS = [
    /\/page\/(\d+)/,         # /page/2
    /[?&]page=(\d+)/,        # ?page=2
    /[?&]p=(\d+)/,           # ?p=2
    /[?&]paged=(\d+)/,       # ?paged=2
    /[?&]offset=(\d+)/,      # ?offset=20
    /[?&]start=(\d+)/,       # ?start=10
    /[?&]after=([^&]+)/,     # ?after=abc123 (cursor)
    /[?&]cursor=([^&]+)/     # ?cursor=xyz
  ].freeze

  # Link text patterns indicating "next page"
  NEXT_LINK_TEXT_PATTERNS = [
    /\Anext\z/i,
    /\Aolder\s*(posts|entries)?\z/i,
    /\Aprevious\s*(posts|entries)?\z/i,  # some blogs use "previous" for older
    /^>+$/,
    /^>>$/,
    /^\u2192$/,              # right arrow
    /^\u00BB$/,              # >>
    /load\s*more/i
  ].freeze

  attr_reader :start_url, :origin, :current_page_number, :next_page_url

  def initialize(start_url:, origin: nil)
    @start_url = start_url
    @origin = origin || URI.parse(start_url).origin
    @current_page_number = 0
    @next_page_url = start_url
    @completed = false
    @fetch_error = nil
  end

  # Iterates through each page of the paginated archive
  #
  # @yield [page_number, page_url, html, articles_data]
  # @yieldparam page_number [Integer] 1-indexed page number
  # @yieldparam page_url [String] URL of the current page
  # @yieldparam html [Nokogiri::HTML::Document] Parsed HTML document
  # @yieldparam articles_data [Array<Hash>] Extracted article data
  # @return [void]
  def each_page
    while @next_page_url
      @current_page_number += 1
      page_url = @next_page_url

      Rails.logger.info("[PaginatedArchiveScraper] Fetching page #{@current_page_number}: #{page_url}")

      begin
        fetch_result = WebFetcher.fetch(page_url)
        html_content = fetch_result[:content]
        html = Nokogiri::HTML(html_content)
      rescue WebFetcher::FetchError => e
        @fetch_error = e
        Rails.logger.error("[PaginatedArchiveScraper] Fetch failed for #{page_url}: #{e.message}")
        break
      end

      # Extract articles from this page
      results = WebProcessor.extract_articles_from_archive(html, page_url)
      articles_data = results.fetch(:articles, [])
      Rails.logger.info("[PaginatedArchiveScraper] Found #{articles_data.length} articles on page #{@current_page_number}")

      # Find next page URL before yielding
      @next_page_url = find_next_page_url(html, page_url)

      yield @current_page_number, page_url, html, articles_data

      # Mark as completed if no next page
      if @next_page_url.nil?
        @completed = true
        Rails.logger.info("[PaginatedArchiveScraper] Reached end of pagination at page #{@current_page_number}")
      end
    end
  end

  # Whether pagination completed naturally (no more pages)
  #
  # @return [Boolean]
  def completed?
    @completed
  end

  # The fetch error if iteration stopped due to a fetch failure
  #
  # @return [WebFetcher::FetchError, nil]
  def fetch_error
    @fetch_error
  end

  # Finds the next page URL from parsed HTML
  #
  # Class method wrapper for use by external callers (e.g., playground).
  # Uses multiple strategies: rel="next", pagination containers, link text, URL patterns.
  #
  # @param html [Nokogiri::HTML::Document] The parsed HTML
  # @param current_url [String] The current page URL
  # @param origin [String] The origin URL for resolving relative links
  # @return [String, nil] The next page URL, or nil if not found
  def self.find_next_page_url(html, current_url, origin: nil)
    origin ||= URI.parse(current_url).origin
    scraper = new(start_url: current_url, origin: origin)
    scraper.send(:find_next_page_url, html, current_url)
  end

  # Extracts a page number from a URL if possible
  #
  # @param url [String] The URL to extract page number from
  # @return [Integer, nil] The page number, or nil if not extractable
  def self.extract_page_number(url)
    return nil if url.blank?

    PAGINATION_URL_PATTERNS.each do |pattern|
      match = url.match(pattern)
      if match
        value = match[1]
        # For offset patterns, return nil (not a simple page number)
        next if pattern.to_s.include?("offset") || pattern.to_s.include?("start")
        # For cursor patterns, return nil
        next if pattern.to_s.include?("after") || pattern.to_s.include?("cursor")

        return value.to_i
      end
    end

    nil
  end

  private

  # Finds the URL of the next page in the pagination sequence
  #
  # @param html [Nokogiri::HTML::Document] The parsed HTML
  # @param current_url [String] The current page URL
  # @return [String, nil] The next page URL, or nil if not found
  def find_next_page_url(html, current_url)
    # Strategy 1: Look for rel="next" in <head>
    next_url = find_rel_next_in_head(html)
    return resolve_url(next_url) if next_url

    # Strategy 2: Look for anchors with rel="next"
    next_url = find_rel_next_anchor(html)
    return resolve_url(next_url) if next_url

    # Strategy 3: Look in pagination containers
    next_url = find_in_pagination_container(html, current_url)
    return resolve_url(next_url) if next_url

    # Strategy 4: Look for "next" link text anywhere
    next_url = find_next_by_text(html)
    return resolve_url(next_url) if next_url

    # Strategy 5: Look for links pointing to current_url/page/2/ pattern
    next_url = find_next_by_url_pattern(html, current_url)
    return resolve_url(next_url) if next_url

    nil
  end

  # Looks for <link rel="next"> in document head
  #
  # @param html [Nokogiri::HTML::Document]
  # @return [String, nil]
  def find_rel_next_in_head(html)
    link = html.at_css('head link[rel="next"]')
    link&.[]("href")
  end

  # Looks for anchors with rel="next"
  #
  # @param html [Nokogiri::HTML::Document]
  # @return [String, nil]
  def find_rel_next_anchor(html)
    anchor = html.at_css('a[rel="next"]')
    anchor&.[]("href")
  end

  # Looks for next link in pagination containers
  #
  # @param html [Nokogiri::HTML::Document]
  # @param current_url [String]
  # @return [String, nil]
  def find_in_pagination_container(html, current_url)
    # Common pagination container selectors
    # Note: Nokogiri doesn't support case-insensitive attribute selectors, so we use multiple variants
    containers = html.css(
      ".pagination, .pager, .page-numbers, nav.pages, " \
      "nav[role='navigation'], [aria-label*='pagination'], [aria-label*='Pagination'], " \
      ".nav-links, .post-navigation, .pagination-container"
    )

    return nil if containers.empty?

    current_page_number = self.class.extract_page_number(current_url) || 1

    containers.each do |container|
      container.css("a[href]").each do |link|
        href = link["href"]
        next if href.blank?

        # Check if this is a "next" type link
        link_text = link.text.strip.downcase
        next if link_text.empty?

        # Check by link text
        if next_link_text?(link_text)
          return href
        end

        # Check if this links to next page number
        link_page = self.class.extract_page_number(href)
        if link_page && link_page == current_page_number + 1
          return href
        end
      end
    end

    nil
  end

  # Looks for next link by common text patterns
  #
  # @param html [Nokogiri::HTML::Document]
  # @return [String, nil]
  def find_next_by_text(html)
    html.css("a[href]").each do |link|
      href = link["href"]
      next if href.blank?
      next if href.start_with?("#", "mailto:", "javascript:")

      link_text = link.text.strip

      if next_link_text?(link_text)
        resolved = resolve_url(href)
        # Verify it's a same-origin link
        return href if resolved
      end
    end

    nil
  end

  # Checks if link text matches "next page" patterns
  #
  # @param text [String] The link text
  # @return [Boolean]
  def next_link_text?(text)
    return false if text.blank?
    NEXT_LINK_TEXT_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  # Looks for links pointing to current_url/page/2/ pattern
  #
  # Detects pagination links where the href is the current URL with /page/N/ appended.
  # This handles icon-only links or links with non-standard text.
  #
  # @param html [Nokogiri::HTML::Document]
  # @param current_url [String]
  # @return [String, nil]
  def find_next_by_url_pattern(html, current_url)
    current_page = self.class.extract_page_number(current_url) || 1
    next_page = current_page + 1

    # Build expected next page URL pattern based on current URL
    # Remove trailing slash for consistent matching
    base_url = current_url.chomp("/")

    # If current URL already has /page/N, replace it
    if base_url =~ /\/page\/\d+$/
      expected_next = base_url.sub(/\/page\/\d+$/, "/page/#{next_page}")
    else
      expected_next = "#{base_url}/page/#{next_page}"
    end

    html.css("a[href]").each do |link|
      href = link["href"]
      next if href.blank?

      resolved = resolve_url(href)
      next unless resolved

      # Normalize for comparison (remove trailing slash)
      normalized_href = resolved.chomp("/")
      normalized_expected = expected_next.chomp("/")

      return href if normalized_href == normalized_expected
    end

    nil
  end

  # Resolves a potentially relative URL to absolute
  #
  # Safety feature: Only accepts URLs from the same origin to prevent:
  # - Off-site navigation that could lead to infinite external links
  # - Cross-site attacks or traps
  # - Unintended scraping of other domains
  #
  # Returns nil if the URL is off-origin or invalid.
  #
  # @param href [String] The href to resolve
  # @return [String, nil] The resolved absolute URL, or nil if off-origin/invalid
  def resolve_url(href)
    return nil if href.blank?

    uri = URI.parse(href)
    if uri.absolute?
      # Only accept URLs from the same origin (safety check)
      return nil unless href.start_with?(@origin)
      href
    else
      "#{@origin}#{href.start_with?('/') ? '' : '/'}#{href}"
    end
  rescue URI::InvalidURIError
    nil
  end
end
