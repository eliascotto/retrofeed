class SiteProfile
  # Class names as strings so the constants resolve lazily. Referencing the
  # subclasses directly here would load them before this class body finishes
  # defining the DSL methods they call (host, date, ...), a circular load.
  REGISTRY = {
    "paulgraham.com" => "SiteProfile::PaulGraham",
    "simonwillison.net" => "SiteProfile::SimonWillison",
    "antirez.com" => "SiteProfile::Antirez",
    "shaggydev.com" => "SiteProfile::ShaggyDev"
  }.freeze

  def self.for(url)
    domain = UrlUtils.extract_domain(url)
    return nil if domain.blank?
    normalized = domain.downcase.delete_prefix("www.")
    REGISTRY[normalized]&.constantize
  rescue UrlUtils::InvalidUrlError
    nil
  end

  # Config properties.
  #
  # @host [String] The host this rule applies to
  # @date_config [Hash] Configuration for extracting date
  # @author_config [Hash] Configuration for extracting author
  # @title_config [Hash] Configuration for extracting title
  # @container_config [Hash] Configuration for extracting container
  # @allowed_external_domains [Array<String>] Allowed external domains

  # Config structure Hash.
  #
  # {
  #   css:          "meta[property='article:published_time']",  # how to find the element
  #   fallback_css: "time.published",                           # tried if `css` misses
  #   attr:         "content",                                  # read this attribute (default: text)
  #   regex:        /By (.+?) on/,                              # optional regex applied to the string
  #   capture:      1,                                          # which capture group to keep
  #   transform:    :iso8601,                                   # final conversion step
  #   static:       "Paul Graham"                               # shortcut: ignore DOM, return this
  # }
  class << self
    def host(host) = @host = host
    def date(**config) = @date_config = config
    def author(**config) = @author_config = config
    def title(**config) = @title_config = config
    def archive_container(**config) = @archive_container_config = config

    def allowed_external_domains(domains)
      if domains.is_a?(Array)
        @allowed_external_domains = domains
      else
        raise ArgumentError, "allowed_external_domains must be an array"
      end
    end

    # Known archive URL: skip detection and use this URL directly.
    # Called with a URL it declares the value; called bare it reads it back.
    def archive_url(url = nil)
      if url
        @archive_url = url
      else
        @archive_url
      end
    end

    # Custom detector class: hands detection and extraction to a dedicated
    # class (the escape hatch for sites the default pipeline can't handle).
    def detector(klass = nil)
      if klass
        @detector = klass
      else
        @detector
      end
    end

    def custom_detector(url) = @detector&.new(url)

    def extract_date(doc, url) = extract_field(@date_config, doc)
    def extract_author(doc, url) = extract_field(@author_config, doc)
    def extract_title(doc, url) = extract_field(@title_config, doc)
    def extract_archive_container(doc, url) = extract_field(@archive_container_config, doc)

    def allowed_external_link?(href)
      return false if @allowed_external_domains.nil?

      href_host = UrlUtils.extract_domain(href)
      @allowed_external_domains.any? { |domain| href_host == domain || href_host.end_with?(".#{domain}") }
    end

    private
      def extract_field(config, doc)
        # Static value
        return nil if config.nil?
        return config[:static] if config[:static]

        # DOM extraction
        return nil if doc.nil?
        node = doc.at_css(config[:css]) || (config[:fallback_css] && doc.at_css(config[:fallback_css]))
        return nil unless node

        value = config[:attr] ? node[config[:attr]] : node.text.strip
        return nil if value.blank?

        if config[:regex]
          match = value.match(config[:regex])
          value = match && match[config[:capture] || 0]
          return nil unless value
        end

        apply_transform(value, config[:transform])
      end

      def apply_transform(value, transform)
        case transform
        when :iso8601       then Date.iso8601(value) rescue nil
        when :relative_date then DateUtils.parse_relative_date(value)
        when :strip         then value.strip
        when Proc           then transform.call(value)
        when nil            then value
        end
      end
  end
end
