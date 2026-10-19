# Base class for custom archive detectors
#
# Custom detectors should inherit from this class and implement:
#   - detect: Returns an ArchivePageDetector::Result or nil
#   - extract_articles: Returns an array of article hashes
#
# Example:
#   class ArchivePageDetector::MyCustomDetector < ArchivePageDetector::BaseDetector
#     def detect
#       # Custom detection logic
#       Result.new(url: @url, method: "custom", confidence_score: 1.0, ...)
#     end
#
#     def extract_articles(html, base_url)
#       # Custom extraction logic
#       [{ title: "Post", url: "https://...", date: Date.today, tags: [] }]
#     end
#   end
#
class ArchivePageDetector
  class BaseDetector
    attr_reader :url, :origin

    def initialize(url, fetcher: WebFetcher)
      @url = UrlUtils.validate_and_normalize_url(url)
      @origin = URI.parse(@url).origin
      @fetcher = fetcher
    end

    # Detects the archive page for this website
    # Subclasses must implement this method
    #
    # @return [ArchivePageDetector::Result, nil] Detection result, or nil to fall back to default
    def detect
      raise NotImplementedError, "Subclasses must implement #detect"
    end

    # Extracts articles from an archive page
    # Subclasses must implement this method
    #
    # @param html [Nokogiri::HTML::Document] The parsed HTML document
    # @param base_url [String] The base URL of the page
    # @return [Array<Hash>] Array of article hashes with :title, :url, :date, :tags
    def extract_articles(html, base_url)
      raise NotImplementedError, "Subclasses must implement #extract_articles"
    end

    # Whether this detector handles article extraction
    # Override to return false if using default extraction
    #
    # @return [Boolean]
    def handles_extraction?
      true
    end

    protected

    # Creates a Result struct for returning from detect
    #
    # @param url [String] The detected archive URL
    # @param method [String] The detection method name
    # @param confidence_score [Float] Confidence score (0.0-1.0)
    # @param pagination_detected [Boolean] Whether pagination was detected
    # @param notes [String] Additional notes
    # @return [ArchivePageDetector::Result]
    def build_result(url:, method:, confidence_score:, pagination_detected: false, notes: nil)
      ArchivePageDetector::Result.new(
        url: url,
        method: method,
        confidence_score: confidence_score,
        pagination_detected: pagination_detected,
        notes: notes
      )
    end

    # Fetches and parses HTML from a URL
    #
    # @param url [String] The URL to fetch
    # @return [Array(Nokogiri::HTML::Document, String), nil] Array of [html, final_url] or nil on error
    def fetch_and_parse(url)
      result = safe_fetch(url)
      return nil unless result

      html = Nokogiri::HTML(result[:content])
      [ html, result[:final_url] ]
    end

    # Safely fetches content, returning nil on error
    #
    # @param url [String] The URL to fetch
    # @return [Hash, nil] Hash with :content and :final_url, or nil on error
    def safe_fetch(url)
      @fetcher.fetch(url)
    rescue WebFetcher::FetchError => e
      Rails.logger.debug("[#{self.class.name}] Fetch failed for #{url}: #{e.message}")
      nil
    end

    # Safely performs HEAD request, returning nil on error
    #
    # @param url [String] The URL to probe
    # @return [Hash, nil]
    def safe_head(url)
      @fetcher.head(url)
    rescue WebFetcher::FetchError => e
      Rails.logger.debug("[#{self.class.name}] HEAD failed for #{url}: #{e.message}")
      nil
    end

    # Resolves a potentially relative URL to absolute
    #
    # @param href [String] The href to resolve
    # @return [String, nil]
    def resolve_url(href)
      return nil if href.blank?

      uri = URI.parse(href)
      if uri.absolute?
        href
      else
        "#{@origin}#{href.start_with?('/') ? '' : '/'}#{href}"
      end
    rescue URI::InvalidURIError
      nil
    end

    # Logs an info message with the detector class name
    #
    # @param message [String] The message to log
    def log_info(message)
      Rails.logger.info("[#{self.class.name}] #{message}")
    end

    # Logs a debug message with the detector class name
    #
    # @param message [String] The message to log
    def log_debug(message)
      Rails.logger.debug("[#{self.class.name}] #{message}")
    end

    # Logs a warning message with the detector class name
    #
    # @param message [String] The message to log
    def log_warn(message)
      Rails.logger.warn("[#{self.class.name}] #{message}")
    end
  end
end
