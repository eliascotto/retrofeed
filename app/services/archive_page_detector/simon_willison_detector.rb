# Custom archive detector for simonwillison.net
#
# Simon Willison's blog has a unique archive structure:
# - Archive is organized by year: https://simonwillison.net/2024/
# - Years range from 2002 to the current year
# - Each year page lists months with entry counts (e.g., "August - 12 entries, 22 links, 4 quotes")
# - Month pages (e.g., /2010/Mar/) are navigation pages, not articles
# - Article URLs have format: /YYYY/Mon/DD/slug/ (e.g., /2010/Aug/24/what-is-the-history/)
# - Article dates are extracted from the title format: "25th: Article Title"
#
class ArchivePageDetector
  class SimonWillisonDetector < BaseDetector
    # Year the blog started
    START_YEAR = 2002

    # Month abbreviations used in URLs
    MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze

    # Pattern to match year URLs: /2024/ or /2024
    YEAR_URL_PATTERN = %r{/(\d{4})/?$}

    # Pattern to match month URLs: /2024/Jan/ or /2024/Jan
    MONTH_URL_PATTERN = %r{/(\d{4})/(#{MONTHS.join('|')})/?$}i

    # Pattern to match article URLs: /2024/Jan/15/article-slug/
    ARTICLE_URL_PATTERN = %r{/(\d{4})/(#{MONTHS.join('|')})/(\d{1,2})/([^/]+)/?$}i

    # Pattern to extract day from title: "25th: Article Title" or "1st: Article Title"
    DAY_PATTERN = /^(\d{1,2})(?:st|nd|rd|th):\s*(.+)$/i

    # Detects the archive structure for simonwillison.net
    # Returns the most recent year page as the primary archive
    #
    # @return [ArchivePageDetector::Result]
    def detect
      log_info("Starting detection for simonwillison.net: #{@url}")

      # Check if URL is already a year page
      if year_url?(@url)
        log_info("URL is a year page, using directly")
        return build_result(
          url: @url,
          method: "custom_simonwillison",
          confidence_score: 1.0,
          pagination_detected: true,
          notes: "Year-based archive page (simonwillison.net custom detector)"
        )
      end

      # If URL is an article or month page, redirect to the year
      if (year = extract_year_from_url(@url))
        year_url = "#{@origin}/#{year}/"
        log_info("Extracted year #{year} from URL, using year page: #{year_url}")
        return build_result(
          url: year_url,
          method: "custom_simonwillison",
          confidence_score: 1.0,
          pagination_detected: true,
          notes: "Redirected to year page from #{@url}"
        )
      end

      # Default to current year's archive
      current_year = Time.current.year
      year_url = "#{@origin}/#{current_year}/"

      # Verify the year page exists
      head_result = safe_head(year_url)
      if head_result && (200..299).cover?(head_result[:status])
        log_info("Using current year archive: #{year_url}")
        return build_result(
          url: year_url,
          method: "custom_simonwillison",
          confidence_score: 1.0,
          pagination_detected: true,
          notes: "Current year archive page"
        )
      end

      # Fall back to previous year if current year doesn't exist yet
      previous_year_url = "#{@origin}/#{current_year - 1}/"
      log_info("Current year not available, trying previous year: #{previous_year_url}")
      build_result(
        url: previous_year_url,
        method: "custom_simonwillison",
        confidence_score: 0.95,
        pagination_detected: true,
        notes: "Previous year archive page (current year not available)"
      )
    end

    # Extracts articles from a year or month page
    # For year pages, fetches each month page and extracts articles
    # For month pages, extracts article links directly
    #
    # @param html [Nokogiri::HTML::Document] The parsed HTML document
    # @param base_url [String] The base URL of the page
    # @return [Array<Hash>] Array of article hashes
    def extract_articles(html, base_url)
      log_info("Extracting articles from: #{base_url}")

      if year_url?(base_url)
        extract_articles_from_year_page(html, base_url)
      elsif month_url?(base_url)
        year, month = extract_year_month_from_url(base_url)
        extract_articles_from_month_page(html, base_url, year, month)
      else
        # Try to determine if this is a year or month page by content
        log_warn("URL doesn't match expected patterns, attempting content-based detection")
        extract_articles_from_year_page(html, base_url)
      end
    end

    private

    # Checks if a URL is a year page
    def year_url?(url)
      url.match?(YEAR_URL_PATTERN)
    end

    # Checks if a URL is a month page
    def month_url?(url)
      url.match?(MONTH_URL_PATTERN)
    end

    # Checks if a URL is an article page
    def article_url?(url)
      url.match?(ARTICLE_URL_PATTERN)
    end

    # Extracts year from any URL on the site
    def extract_year_from_url(url)
      # Try article pattern first
      if (match = url.match(ARTICLE_URL_PATTERN))
        return match[1].to_i
      end

      # Try month pattern
      if (match = url.match(MONTH_URL_PATTERN))
        return match[1].to_i
      end

      # Try year pattern
      if (match = url.match(YEAR_URL_PATTERN))
        return match[1].to_i
      end

      nil
    end

    # Extracts year and month from a month URL
    def extract_year_month_from_url(url)
      if (match = url.match(MONTH_URL_PATTERN))
        year = match[1].to_i
        month_abbr = match[2]
        month = MONTHS.index { |m| m.casecmp(month_abbr).zero? }
        return [ year, month + 1 ] if month
      end
      [ nil, nil ]
    end

    # Extracts year, month, and day from an article URL
    def extract_date_from_article_url(url)
      if (match = url.match(ARTICLE_URL_PATTERN))
        year = match[1].to_i
        month_abbr = match[2]
        day = match[3].to_i
        month_index = MONTHS.index { |m| m.casecmp(month_abbr).zero? }

        if month_index
          begin
            return Date.new(year, month_index + 1, day)
          rescue ArgumentError
            # Invalid date
            return nil
          end
        end
      end
      nil
    end

    # Extracts articles directly from a year page
    # Year pages contain all article links inline (no need to fetch month pages)
    def extract_articles_from_year_page(html, base_url)
      articles = []
      year = extract_year_from_url(base_url)

      log_info("Extracting articles directly from year page: #{year}")

      # Find all article links on the year page
      html.css("a[href]").each do |link|
        href = link["href"]
        next unless href

        full_url = resolve_url(href)
        next unless full_url
        next unless article_url?(full_url)

        # Extract date from URL
        date = extract_date_from_article_url(full_url)

        # Extract title from the link text
        title = extract_article_title(link)
        next if title.blank?

        # Skip if we already have this article
        next if articles.any? { |a| a[:url] == full_url }

        articles << {
          title: title,
          url: full_url,
          date: date,
          tags: []
        }
      end

      log_info("Total articles extracted from year #{year}: #{articles.length}")
      articles
    end

    # Extracts articles from a month page
    def extract_articles_from_month_page(html, base_url, year, month)
      articles = []

      # Find all links that look like article URLs
      html.css("a[href]").each do |link|
        href = link["href"]
        next unless href

        full_url = resolve_url(href)
        next unless full_url
        next unless article_url?(full_url)

        # Extract date from URL
        date = extract_date_from_article_url(full_url)

        # Extract title - try to get it from the link text
        title = extract_article_title(link)
        next if title.blank?

        # Skip if we already have this article
        next if articles.any? { |a| a[:url] == full_url }

        articles << {
          title: title,
          url: full_url,
          date: date,
          tags: []
        }
      end

      articles
    end

    # Pattern to match time-based titles (quotes, links, notes use times like "12:48 am")
    TIME_TITLE_PATTERN = /^\d{1,2}:\d{2}\s*[ap]m$/i

    # Navigation and non-article text patterns
    SKIP_TITLE_PATTERNS = [
      /^last\s+year$/i,
      /^next\s+year$/i,
      /^previous$/i,
      /^next$/i,
      /^home$/i,
      /^archive$/i
    ].freeze

    # Extracts article title from a link element
    # Handles format like "25th: Article Title" and cleans it up
    #
    # Simon's site has different content types:
    # - Entries (articles): Have real titles like "Introducing gisthost.github.io"
    # - Links/Quotes/Notes: Have time-based titles like "12:48 am"
    #
    # This method filters out non-article content by rejecting time-based titles.
    def extract_article_title(link)
      text = link.text.strip

      # Try to extract title from "25th: Title" format
      if (match = text.match(DAY_PATTERN))
        title = match[2].strip
        return nil if looks_like_non_article?(title)
        return title
      end

      # If no day pattern, use the text as-is (if it looks like a title)
      return nil if text.length < 5  # Too short to be a title
      return nil if text.length > 500  # Too long to be a title
      return nil if text.match?(/^\d+$/)  # Just a number
      return nil if looks_like_non_article?(text)

      text
    end

    # Checks if a title looks like non-article content (quotes, links, notes)
    #
    # @param title [String] The title to check
    # @return [Boolean] true if this looks like non-article content
    def looks_like_non_article?(title)
      return true if title.blank?

      # Time-based titles indicate quotes, links, or notes (e.g., "12:48 am")
      return true if title.match?(TIME_TITLE_PATTERN)

      # Navigation text
      return true if SKIP_TITLE_PATTERNS.any? { |pattern| title.match?(pattern) }

      false
    end
  end
end
