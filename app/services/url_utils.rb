class UrlUtils
  class InvalidUrlError < StandardError; end

  # Validates and normalizes a URL
  #
  # @param url [String] The URL to validate and normalize
  # @return [String] The normalized URL
  def self.validate_and_normalize_url(url)
    raise InvalidUrlError, "URL cannot be blank" if url.blank?

    # Parse the URL
    uri = Addressable::URI.parse(url.to_s.strip)

    # Auto-add https:// if scheme is missing
    unless uri.scheme
      uri = Addressable::URI.parse("https://#{url.to_s.strip}")
    end

    # Validate scheme is http or https
    unless uri.scheme.match?(/^https?$/)
      raise InvalidUrlError, "URL must use http:// or https:// scheme (got: #{uri.scheme})"
    end

    # Validate host is present
    unless uri.host
      raise InvalidUrlError, "URL must have a valid host"
    end

    # Normalize and return the URL
    uri.normalize.to_s
  rescue Addressable::URI::InvalidURIError => e
    raise InvalidUrlError, "Invalid URL format: #{e.message}"
  end

  # Extracts the domain from a URL safely. Returns nil if
  # error or domain not present.
  #
  # @param url [String] The URL to extract the domain from
  # @return [String, nil] The domain of the URL, or nil if invalid
  def self.extract_domain(url)
    return nil if url.blank?

    begin
      validated_url = validate_and_normalize_url(url)
      uri = Addressable::URI.parse(validated_url)
      domain = uri.host&.downcase
      return nil unless domain

      domain.sub(/\Awww\./i, "")
    rescue Addressable::URI::InvalidURIError
      nil
    end
  end

  def self.extract_origin(url)
    Addressable::URI.parse(url).origin
  end

  # Returns true if the url is potentially safe agains SSRF attacks.
  # Not enough to completely trust without network blocks.
  def self.safe_url_for_processing?(url)
    return true if Rails.env.local?
    uri = URI.parse(url)
    return false unless SsrfFilter::DEFAULT_SCHEME_WHITELIST.include?(uri.scheme)

    ips = SsrfFilter::DEFAULT_RESOLVER.call(uri.hostname)
    return false if ips.empty?

    # Reject if ANY resolved IP is unsafe (defeats split-horizon tricks where
    # one A record is public and another is private)
    ips.none? { |ip| SsrfFilter.send(:unsafe_ip_address?, ip) }
  rescue URI::InvalidURIError, Resolv::ResolvError
    false
  end

  # Resolves a relative or absolute URL to an absolute URL using a base URL
  #
  # @param url [String] The URL to resolve (can be relative or absolute)
  # @param base_url [String] The base URL to use for resolving relative URLs
  # @return [String, nil] The resolved absolute URL, or nil if invalid
  def self.resolve_url(url, base_url)
    return nil if url.blank? || base_url.blank?

    url_str = url.to_s.strip
    uri = Addressable::URI.parse(url_str)

    if uri.absolute?
      uri.normalize.to_s if uri.scheme&.match?(/^https?$/)
    else
      base_uri = Addressable::URI.parse(base_url)

      # Bare relative paths (e.g. "post.html" against "/blog") need directory-style
      # base resolution to yield "/blog/post.html" instead of "/post.html".
      if !url_str.start_with?("/") && !base_uri.path.to_s.end_with?("/") && !base_uri.path.to_s.match?(/\.[a-z0-9]{2,4}$/i)
        base_uri = base_uri.dup
        base_uri.path = "#{base_uri.path}/"
      end

      base_uri.join(uri).normalize.to_s
    end
  rescue Addressable::URI::InvalidURIError
    nil
  end

  # Checks if a URL is a local link (same domain as the base URL)
  #
  # @param url [String] The URL to check
  # @param base_url [String] The base URL to compare against
  # @return [Boolean] true if the URL is on the same domain
  def self.is_local_link?(url, base_url)
    return false if url.blank? || base_url.blank?

    begin
      resolved_url = resolve_url(url, base_url)
      return false unless resolved_url

      url_uri = Addressable::URI.parse(resolved_url)
      base_uri = Addressable::URI.parse(base_url)

      url_uri.host == base_uri.host
    rescue Addressable::URI::InvalidURIError
      false
    end
  end

  # Extracts the path from a URL, resolving relative URLs to absolute first
  #
  # @param url [String] The URL to extract the path from
  # @param base_url [String] The base URL to use for resolving relative URLs
  # @return [String, nil] The path component of the URL, or nil if invalid
  def self.extract_path(url, base_url)
    return nil if url.blank? || base_url.blank?

    begin
      resolved_url = resolve_url(url, base_url)
      return nil unless resolved_url

      uri = Addressable::URI.parse(resolved_url)
      uri.path
    rescue Addressable::URI::InvalidURIError
      nil
    end
  end

  # Lowercase path segments of an href, ignoring query/fragment and file
  # extensions: "/blog/all/" -> ["blog", "all"], "/blog.html" -> ["blog"],
  # "/2019/9/4/using-rust-to-build-a-blog-site" -> [..., "using-rust-to-build-a-blog-site"]
  #
  # @param href [String] The URL to extract path segments from
  # @return [Array<String>] The path segments of the URL
  def self.path_segments(href)
    path = Addressable::URI.parse(href).path.to_s.downcase
    path.split("/").reject(&:empty?).map { |seg| seg.sub(/\.[a-z0-9]+\z/, "") }
  rescue Addressable::URI::InvalidURIError
    []
  end

  # Extract HTTP context from an exception
  #
  # @param exception [Exception] The exception to extract HTTP context from
  # @return [Hash] The HTTP context
  def self.http_context_from_exception(exception)
    return {} unless exception.respond_to?(:http_status)

    {
      http_status: exception.http_status,
      http_method: exception.respond_to?(:http_method) ? exception.http_method : "GET",
      content_type: exception.respond_to?(:content_type) ? exception.content_type : nil,
      headers: exception.respond_to?(:headers) ? exception.headers : nil
    }.compact
  end
end
