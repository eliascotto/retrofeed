# Extracts favicon URLs from HTML pages
#
# Usage:
#   FaviconExtractor.extract_favicon_url(html, "https://example.com")
#   => "https://example.com/favicon.ico"
#
# The extractor looks for favicons in this priority order:
#   1. <link rel="icon"> or <link rel="shortcut icon">
#   2. <link rel="apple-touch-icon">
#   3. Default /favicon.ico at site root
#
class FaviconExtractor
  # CSS selectors for favicon link elements, in priority order
  FAVICON_SELECTORS = [
    'link[rel="icon"]',
    'link[rel="shortcut icon"]',
    'link[rel="ICON"]',
    'link[rel="SHORTCUT ICON"]',
    'link[rel~="icon"]',
    'link[rel="apple-touch-icon"]',
    'link[rel="apple-touch-icon-precomposed"]'
  ].freeze

  # Extracts the favicon URL from an HTML document
  #
  # @param html [String, Nokogiri::HTML::Document] The HTML content or parsed document
  # @param base_url [String] The base URL of the page (used to resolve relative URLs)
  # @return [String, nil] The absolute favicon URL, or nil if not found
  def self.extract_favicon_url(html, base_url)
    new(html, base_url).extract
  end

  def initialize(html, base_url)
    @html = html.is_a?(Nokogiri::HTML::Document) ? html : Nokogiri::HTML(html)
    @base_url = base_url
    @base_uri = URI.parse(base_url) rescue nil
  end

  # Extracts the favicon URL
  #
  # @return [String, nil] The absolute favicon URL, or nil if not found
  def extract
    # Try to find favicon in link tags
    favicon_url = find_favicon_in_links

    # If no favicon found in links, try default /favicon.ico
    favicon_url ||= default_favicon_url

    favicon_url
  end

  private

  # Searches for favicon URL in link elements
  #
  # @return [String, nil] The favicon URL if found
  def find_favicon_in_links
    FAVICON_SELECTORS.each do |selector|
      @html.css(selector).each do |link|
        href = link["href"]
        next if href.blank?

        # Resolve to absolute URL
        absolute_url = resolve_url(href)
        return absolute_url if absolute_url.present?
      end
    end

    nil
  end

  # Returns the default favicon.ico URL at the site root
  #
  # @return [String, nil] The default favicon URL
  def default_favicon_url
    return nil unless @base_uri

    begin
      URI.join(@base_uri.origin, "/favicon.ico").to_s
    rescue URI::Error
      nil
    end
  end

  # Resolves a potentially relative URL to an absolute URL
  #
  # @param href [String] The href attribute value
  # @return [String, nil] The absolute URL, or nil if invalid
  def resolve_url(href)
    return nil if href.blank?
    return nil unless @base_uri

    begin
      # Handle protocol-relative URLs (//example.com/favicon.ico)
      if href.start_with?("//")
        return "#{@base_uri.scheme}:#{href}"
      end

      # Handle absolute URLs
      if href.start_with?("http://", "https://")
        return href
      end

      # Handle data URIs (skip them, we can't store these efficiently)
      return nil if href.start_with?("data:")

      # Resolve relative URLs
      URI.join(@base_uri.origin, href).to_s
    rescue URI::Error => e
      Rails.logger.debug("[FaviconExtractor] Failed to resolve URL '#{href}': #{e.message}")
      nil
    end
  end
end
