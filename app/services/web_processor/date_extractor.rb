class WebProcessor
  module DateExtractor
    extend self

    # URL date formats we recognize, ordered most-specific first. Each regex uses
    # named captures and is paired with a layout that tells date_from_match how to
    # map the captured segments onto year/month/day:
    #
    #   :year_first — ISO 8601 and slash variants: /2024/01/15, /2024-01-15, /2024/1/5,
    #                 and prefixed paths like /blog/2024/01/15/slug. Month-then-day.
    #   :year_last  — regional day/month-first formats: /15-01-2024, /01/15/2024.
    #   :year_month — month-level archives with no day: /2024/01, /2024-01.
    #
    # Segments are left loose (\d{1,2}) and validated by Date.new instead of the
    # regex, so out-of-range numbers like /2024/77/88 simply fail to build a date.
    # Years are bounded to 19xx/20xx so arbitrary numeric path segments don't read
    # as dates.
    DATE_URL_PATTERNS = [
      [ :year_first, %r{/(?<year>(?:19|20)\d{2})[/\-](?<n1>\d{1,2})[/\-](?<n2>\d{1,2})(?:[/\-T]|$)} ],
      [ :year_last,  %r{/(?<n1>\d{1,2})[/\-](?<n2>\d{1,2})[/\-](?<year>(?:19|20)\d{2})(?:[/\-]|$)} ],
      [ :year_month, %r{/(?<year>(?:19|20)\d{2})[/\-](?<n1>\d{1,2})(?:[/\-]|$)} ]
    ].freeze

    # Extracts date from a document using rule-based extraction first to find the correct
    # date container element, then extracts the date from that element.
    # Uses a priority-ordered strategy:
    #   1. Structured data (JSON-LD, OpenGraph, meta tags) — most reliable
    #   2. Semantic <time datetime="..."> elements
    #   3. Class-based selectors with datetime/title attributes
    #   4. URL path extraction
    #
    # Free-text DOM scanning is intentionally omitted: with strict date parsing,
    # it produces more false negatives than signal, and risks grabbing publish
    # dates of *other* articles in sidebars.
    #
    # @param doc [Nokogiri::HTML4::Document] The document
    # @param url [String, nil] The article URL for fallback extraction
    # @param base_url [String, nil] The base URL
    # @return [Date, nil] The extracted date
    def extract_date(doc, url = nil, base_url = nil)
      return nil if doc.nil?

      host = UrlUtils.extract_domain(url)
      rule = SiteProfile.for(host)
      if rule
        date = rule.extract_date(doc, url)
        return date if date.present?
      end

      extract_from_structured_data(doc) ||
        extract_from_time_element(doc) ||
        extract_from_class_selectors(doc) ||
        extract_from_url_fallback(url, base_url)
    end

    # Extracts date from a container element using a priority-ordered strategy:
    #   1. Structured data (JSON-LD, OpenGraph, meta tags) — most reliable
    #   2. Semantic <time datetime="..."> elements
    #   3. Class-based selectors with datetime/title attributes
    #   4. URL path extraction
    #
    # Free-text DOM scanning is intentionally omitted: with strict date parsing,
    # it produces more false negatives than signal, and risks grabbing publish
    # dates of *other* articles in sidebars.
    #
    # @param container_el [Nokogiri::HTML4::Element] The container element
    # @param url [String, nil] The article URL for fallback extraction
    # @param base_url [String, nil] The base URL
    # @return [Date, nil] The extracted date
    def extract_date_from_el(container_el, url=nil, base_url=nil)
      extract_from_structured_data(container_el) ||
        extract_from_time_element(container_el) ||
        extract_from_class_selectors(container_el) ||
        extract_from_url_fallback(url, base_url)
    end

    # Extracts a date embedded in a URL, resolving relative URLs first.
    #
    # @param url [String] The URL to extract date from
    # @param base_url [String] The base URL
    # @return [Date, nil] Extracted date or nil
    def extract_date_from_url(url, base_url)
      url_path = UrlUtils.extract_path(url, base_url)
      if url_path
        extract_date_from_path(url_path)
      else
        nil
      end
    end

    # Extracts a date embedded in a URL path by trying each known date format.
    # Returns the first match that resolves to a real calendar date.
    #
    # @param path [String] The URL path (e.g. "/2024/01/15/my-post")
    # @return [Date, nil] Extracted date or nil
    def extract_date_from_path(path)
      return nil if path.blank?

      DATE_URL_PATTERNS.each do |layout, pattern|
        if match = path.match(pattern)
          date = date_from_match(match, layout)
          return date if date
        end
      end
      nil
    end

    private
      # Highest signal: sites explicitly publish dates here for search engines.
      def extract_from_structured_data(container)
        # 1a. JSON-LD
        container.css('script[type="application/ld+json"]').each do |script|
          data = JSON.parse(script.content) rescue next
          date_string = find_date_in_json_ld(data)
          next unless date_string

          result = try_parse_date(date_string, "structured data")
          return result if result
        end

        # 1b. Meta tags (OpenGraph, article:published_time, etc.)
        meta_selectors = [
          'meta[property="article:published_time"]',
          'meta[property="article:modified_time"]',
          'meta[name="date"]',
          'meta[name="pubdate"]',
          'meta[name="publish-date"]',
          'meta[itemprop="datePublished"]'
        ]
        meta_selectors.each do |selector|
          content = container.at_css(selector)&.[]("content")
          next if content.blank?

          result = try_parse_date(content, "meta tag selector: #{selector}")
          return result if result
        end

        nil
      end

      # Recursively searches JSON-LD (which may be a hash, array, or nested @graph)
      # for the first datePublished / dateCreated field.
      def find_date_in_json_ld(data)
        case data
        when Array
          data.each { |item| result = find_date_in_json_ld(item); return result if result }
        when Hash
          %w[datePublished dateCreated dateModified].each do |key|
            return data[key] if data[key].is_a?(String)
          end
          data.each_value { |v| result = find_date_in_json_ld(v); return result if result }
        end
        nil
      end

      # Prefer machine-readable <time datetime="..."> across the whole container
      # before falling back to any <time> element's title/text content.
      def extract_from_time_element(container)
        time_elements = container.css("time")

        # Pass 1 (strict): explicit datetime attributes
        time_elements.each do |elem|
          datetime = elem["datetime"]
          next if datetime.blank?

          result = try_parse_date(datetime, "time element datetime attribute")
          return result if result
        end

        # Pass 2 (loose): title attribute or inner text
        time_elements.each do |elem|
          [elem["title"], elem.text.strip].each do |candidate|
            next if candidate.blank?

            result = try_parse_date(candidate, "time element title or text")
            return result if result
          end
        end

        nil
      end

      # Class-based selectors, but prefer datetime/title attributes over inner text
      # (text often contains "Updated 2 hours ago" which won't parse strictly).
      def extract_from_class_selectors(container)
        selectors = [
          '[class*="published"]',
          '[class*="publish-date"]',
          '[class*="post-date"]',
          '[class*="article-date"]',
          '[itemprop="datePublished"]',
          '[class*="info"]',
          '[class*="date"]' # broadest — last
        ]

        selectors.each do |selector|
          container.css(selector).each do |elem|
            [ elem["datetime"], elem["title"], elem["data-date"], elem.text.strip ].compact.each do |candidate|
              next if candidate.blank?

              result = try_parse_date(candidate, "class selector: #{selector}")
              return result if result
            end
          end
        end

        nil
      end

      def extract_from_url_fallback(url, base_url)
        return nil unless url && base_url

        parsed = extract_date_from_url(url, base_url)

        if parsed
          Rails.logger.info("[DateExtractor] Extracted date from URL: #{url} -> #{parsed}")
        end
        parsed
      end

      # Maps the segments captured by a DATE_URL_PATTERNS regex onto a Date,
      # according to the pattern's layout.
      def date_from_match(match, layout)
        year = match[:year].to_i

        case layout
        when :year_first
          # ISO/year-first paths are month-then-day; if that is not a real date
          # (e.g. /2024/15/03), retry with the two segments swapped.
          build_date(year, match[:n1].to_i, match[:n2].to_i) ||
            build_date(year, match[:n2].to_i, match[:n1].to_i)
        when :year_last
          date_from_year_last(year, match[:n1].to_i, match[:n2].to_i)
        when :year_month
          build_date(year, match[:n1].to_i, 1)
        end
      end

      # Resolves a day/month-first date (year last). When one segment exceeds 12
      # the assignment is unambiguous; otherwise we assume day-first, the more
      # common international convention (DD-MM-YYYY).
      def date_from_year_last(year, first, second)
        if first > 12
          build_date(year, second, first)
        elsif second > 12
          build_date(year, first, second)
        else
          build_date(year, second, first)
        end
      end

      def build_date(year, month, day)
        Date.new(year, month, day)
      rescue ArgumentError
        nil
      end

      # Helper: absolute OR relative. Use this ONLY in date-intended contexts.
      def try_parse_date(candidate, extracted_from = nil)
        return nil if candidate.blank?

        # Try ISO 8601 first (most reliable for structured data)
        parsed = DateUtils.parse_iso8601_date(candidate) ||
                # Then try absolute dates
                DateUtils.parse_date(candidate) ||
                # Finally try relative dates (e.g., "2 hours ago")
                DateUtils.parse_relative_date(candidate)

        if parsed && extracted_from
          Rails.logger.info("[DateExtractor] Extracted date from #{extracted_from}: #{candidate} -> #{parsed}")
        elsif parsed
          Rails.logger.info("[DateExtractor] Extracted date: #{candidate} -> #{parsed}")
        end

        parsed
      end
  end
end
