# Downloads and attaches favicons to websites using ActiveStorage
#
# Usage:
#   FaviconDownloader.download_and_attach(website, "https://example.com/favicon.ico")
#
# This service:
#   - Fetches favicon content using WebFetcher (respects robots.txt and mock mode)
#   - Validates the content is an image
#   - Attaches the favicon to the website using ActiveStorage
#   - Handles errors gracefully without failing the parent process
#
class FaviconDownloader
  # Maximum favicon file size (256KB should be plenty for a favicon)
  MAX_FAVICON_SIZE = 256 * 1024

  # Supported favicon content types
  VALID_CONTENT_TYPES = %w[
    image/x-icon
    image/vnd.microsoft.icon
    image/png
    image/gif
    image/jpeg
    image/svg+xml
    image/webp
  ].freeze

  # File extension to content type mapping for fallback detection
  EXTENSION_TO_CONTENT_TYPE = {
    ".ico" => "image/x-icon",
    ".png" => "image/png",
    ".gif" => "image/gif",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".svg" => "image/svg+xml",
    ".webp" => "image/webp"
  }.freeze

  # Downloads a favicon and attaches it to a website
  #
  # @param website [Website] The website to attach the favicon to
  # @param favicon_url [String] The URL of the favicon to download
  # @return [Boolean] true if favicon was successfully attached, false otherwise
  def self.download_and_attach(website, favicon_url)
    new(website, favicon_url).download_and_attach
  end

  def initialize(website, favicon_url)
    @website = website
    @favicon_url = favicon_url
    @uri = URI.parse(favicon_url) rescue nil
  end

  # Downloads and attaches the favicon
  #
  # @return [Boolean] true if successful, false otherwise
  def download_and_attach
    return false unless valid_url?

    Rails.logger.info("[FaviconDownloader] Downloading favicon for #{@website.domain}: #{@favicon_url}")

    content = fetch_favicon
    return false unless content

    content_type = detect_content_type(content)
    return false unless valid_content_type?(content_type)

    attach_favicon(content, content_type)
    true
  rescue StandardError => e
    Rails.logger.warn("[FaviconDownloader] Failed to download favicon for #{@website.domain}: #{e.message}")
    false
  end

  private

  # Validates the favicon URL
  #
  # @return [Boolean] true if URL is valid
  def valid_url?
    return false if @favicon_url.blank?
    return false unless @uri

    %w[http https].include?(@uri.scheme)
  end

  # Fetches favicon content from the URL
  #
  # @return [String, nil] The favicon content, or nil if fetch failed
  def fetch_favicon
    fetch_result = WebFetcher.fetch(@favicon_url)
    content = fetch_result[:content]

    if content.nil? || content.empty?
      Rails.logger.warn("[FaviconDownloader] Empty content from #{@favicon_url}")
      return nil
    end

    if content.bytesize > MAX_FAVICON_SIZE
      Rails.logger.warn("[FaviconDownloader] Favicon too large (#{content.bytesize} bytes) from #{@favicon_url}")
      return nil
    end

    content
  rescue WebFetcher::FetchError => e
    Rails.logger.warn("[FaviconDownloader] Fetch error for #{@favicon_url}: #{e.message}")
    nil
  end

  # Detects the content type of the favicon
  #
  # @param content [String] The favicon content
  # @return [String] The detected content type
  def detect_content_type(content)
    # Try to detect from file extension first
    extension = File.extname(@uri.path).downcase
    if EXTENSION_TO_CONTENT_TYPE.key?(extension)
      return EXTENSION_TO_CONTENT_TYPE[extension]
    end

    # Try to detect from magic bytes
    detect_from_magic_bytes(content) || "application/octet-stream"
  end

  # Detects content type from magic bytes
  #
  # @param content [String] The file content
  # @return [String, nil] The detected content type, or nil
  def detect_from_magic_bytes(content)
    bytes = content.bytes.first(8)
    return nil if bytes.empty?

    # PNG: 89 50 4E 47 0D 0A 1A 0A
    if bytes[0..7] == [ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A ]
      return "image/png"
    end

    # GIF: 47 49 46 38
    if bytes[0..3] == [ 0x47, 0x49, 0x46, 0x38 ]
      return "image/gif"
    end

    # JPEG: FF D8 FF
    if bytes[0..2] == [ 0xFF, 0xD8, 0xFF ]
      return "image/jpeg"
    end

    # ICO: 00 00 01 00 or 00 00 02 00
    if bytes[0..3] == [ 0x00, 0x00, 0x01, 0x00 ] || bytes[0..3] == [ 0x00, 0x00, 0x02, 0x00 ]
      return "image/x-icon"
    end

    # WebP: RIFF....WEBP
    if bytes[0..3] == [ 0x52, 0x49, 0x46, 0x46 ] && content.bytes[8..11] == [ 0x57, 0x45, 0x42, 0x50 ]
      return "image/webp"
    end

    # SVG: Check for XML/SVG content
    if content.start_with?("<?xml") || content.start_with?("<svg") || content.include?("<svg")
      return "image/svg+xml"
    end

    nil
  end

  # Validates the content type is a supported image type
  #
  # @param content_type [String] The content type to validate
  # @return [Boolean] true if valid
  def valid_content_type?(content_type)
    unless VALID_CONTENT_TYPES.include?(content_type)
      Rails.logger.warn("[FaviconDownloader] Invalid content type '#{content_type}' from #{@favicon_url}")
      return false
    end

    true
  end

  # Attaches the favicon to the website
  #
  # @param content [String] The favicon content
  # @param content_type [String] The content type
  def attach_favicon(content, content_type)
    filename = generate_filename(content_type)

    @website.favicon.attach(
      io: StringIO.new(content),
      filename: filename,
      content_type: content_type
    )

    Rails.logger.info("[FaviconDownloader] Attached favicon to #{@website.domain} (#{content.bytesize} bytes, #{content_type})")
  end

  # Generates a filename for the favicon
  #
  # @param content_type [String] The content type
  # @return [String] The generated filename
  def generate_filename(content_type)
    extension = case content_type
    when "image/x-icon", "image/vnd.microsoft.icon" then ".ico"
    when "image/png" then ".png"
    when "image/gif" then ".gif"
    when "image/jpeg" then ".jpg"
    when "image/svg+xml" then ".svg"
    when "image/webp" then ".webp"
    else ".ico"
    end

    "favicon#{extension}"
  end
end
