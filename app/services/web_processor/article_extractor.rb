class WebProcessor
  module ArticleExtractor
    # extend self makes the link-level predicates (article_like_path?,
    # excluded_pattern_for_path) callable both as instance methods (when included
    # into the strategies) and at module level, so validation in
    # WebProcessor.contains_valid_archive? shares the same predicate as extraction.
    extend self

    # URL path prefixes that indicate a link is not an article (e.g. category, about, feed).
    # Stored without trailing slash. A path is excluded when it equals a pattern (after
    # normalizing) or is under that path (e.g. /category/tech). Used by article_like_path? and debug.
    ARTICLE_EXCLUDED_PATH_PATTERNS = [
      "/category", "/categories",
      "/tag", "/tags",
      "/page", "/archives", "/newsletter",
      "/about", "/contact", "/author",
      "/search", "/blog/search",
      "/_next", "/icon", "/avi", "/series",
      "/rss", "/feed", "/atom"
    ].freeze

    # Returns the excluded pattern if path is excluded, nil otherwise.
    # Path and patterns are compared after normalizing (no trailing slash).
    # Match: exact or path under pattern (e.g. /about and /about/ excluded; /about-the-passion allowed).
    #
    # @param path [String] The URL path to check
    # @return [String, nil] The matching pattern or nil
    def excluded_pattern_for_path(path)
      return nil if path.blank?
      normalized = path.chomp("/")
      ARTICLE_EXCLUDED_PATH_PATTERNS.find do |pattern|
        normalized == pattern || normalized.start_with?(pattern + "/")
      end
    end

    URL_EXCLUDED_SCHEMES = [ "mailto:", "tel:", "sms:", "facetime:", "skype:", "javascript:" ].freeze

    # Checks if a path looks like an article link (not navigation/category)
    #
    # @param path [String] The path to check
    # @param base_path [String] The base path to exclude
    # @return [Boolean] true if it looks like an article
    def article_like_path?(path, base_path = "/")
      return false if path.blank? || path == "/"
      return false if URL_EXCLUDED_SCHEMES.any? { |scheme| path.start_with?(scheme) }

      # Normalize paths by removing trailing slashes for comparison
      # This ensures /blog and /blog/ are treated as the same page
      normalized_path = path.chomp("/")
      normalized_base = base_path.to_s.chomp("/")

      # Exclude the current page (archive index)
      return false if normalized_path == normalized_base

      # Exclude common non-article paths (exact or under pattern)
      return false if excluded_pattern_for_path(path)

      true
    end

    # Finds article-like links in the HTML
    #
    # @param html [Nokogiri::HTML::Document] The HTML document
    # @param base_url [String] The base URL
    # @return [Array<Nokogiri::XML::Element>] Array of link elements
    def find_article_links(html, base_url)
      find_article_links_with_trace(html, base_url).fetch(:articles, [])
    end

    # Finds article-like links with detailed trace information for debugging
    #
    # @param html [Nokogiri::HTML::Document] The HTML document
    # @param base_url [String] The base URL
    # @return [Array<Array, Array>] [article_links, debug_entries]
    #   - article_links: Array of link elements that passed filtering
    #   - debug_entries: Array of hashes with trace info for each link
    def find_article_links_with_trace(html, base_url)
      base_path = UrlUtils.extract_path(base_url, base_url) || "/"
      normalized_base = base_path.to_s.chomp("/")
      domain = UrlUtils.extract_domain(base_url)
      rule = SiteProfile.for(domain)
      links = html.css("a[href]")
      article_links = []
      debug_entries = []

      links.each do |link|
        href = link["href"]

        # Skip links without href
        unless href
          next
        end

        entry = {
          href: href,
          url: nil,
          path: nil,
          included: false,
          reason: nil
        }

        # Check RSS/Feed links by title
        link_text = link.text.strip.downcase
        if [ "rss", "feed", "atom" ].include?(link_text)
          entry[:reason] = "rss_link"
          debug_entries << entry
          next
        end

        if UrlUtils.is_local_link?(href, base_url)
          path = UrlUtils.extract_path(href, base_url)
          url = UrlUtils.resolve_url(href, base_url)
          entry[:path] = path
          entry[:url] = url

          # Check if it's the current page (self-link)
          normalized_path = path.to_s.chomp("/")
          if normalized_path == normalized_base
            entry[:reason] = "excluded_self"
            debug_entries << entry
            next
          end

          # Check if path is blank or root
          if path.blank? || path == "/"
            entry[:reason] = "excluded_root"
            debug_entries << entry
            next
          end

          # Check for excluded patterns
          matched_pattern = excluded_pattern_for_path(path)
          if matched_pattern
            entry[:reason] = "excluded_pattern:#{matched_pattern}"
            debug_entries << entry
            next
          end

          # This link is article-like
          entry[:included] = true
          entry[:reason] = "article_like"
          debug_entries << entry
          article_links << link
        elsif rule&.allowed_external_link?(href)
          # External link allowed by custom rules
          entry[:url] = href
          entry[:included] = true
          entry[:reason] = "allowed_external"
          debug_entries << entry
          article_links << link
        else
          # External link not allowed
          entry[:url] = UrlUtils.resolve_url(href, base_url) rescue href
          entry[:reason] = "external"
          debug_entries << entry
        end
      end

      { articles: article_links, trace: debug_entries }
    end

    # Extracts title from a container using multiple strategies
    #
    # @param container [Nokogiri::XML::Element] The container element
    # @param link_element [Nokogiri::XML::Element, nil] The link element if known
    # @return [String, nil] The extracted title
    def extract_article_title(container, link_element = nil)
      # Try semantic headings first
      heading = container.css("h1, h2, h3, h4").first
      return heading.text.strip if heading

      # Try class-based selectors
      title_elem = container.css('[class*="title"], [class*="heading"]').first
      return title_elem.text.strip if title_elem

      # Use link text as fallback
      if link_element
        return link_element.text.strip if link_element.text.present?
      end

      # Last resort: container text (may include other content)
      container.text.strip if container.name == "a"
    end

    # Extracts tags from a container
    #
    # @param container [Nokogiri::XML::Element] The container element
    # @return [Array<String>] Array of tag strings
    def extract_tags(container)
      tags = []

      # Try semantic/class-based tag elements
      tag_elems = container.css('[class*="tag"], [class*="category"], [rel="tag"], [rel="category"]')
      tags.concat(tag_elems.map { |tag| tag.text.strip }.reject(&:empty?))

      # Try tag/category links
      tag_links = container.css('a[href*="tag"], a[href*="category"], a[href*="/categories/"]')
      tags.concat(tag_links.map { |link| link.text.strip }.reject(&:empty?))

      tags.uniq
    end

    # Extracts article data from a container
    #
    # @param container [Nokogiri::XML::Element] The container element
    # @param base_url [String] The base URL
    # @return [Hash] Hash with :title, :url, :date, :tags
    def extract_article_data(container, base_url)
      data = {
        title: nil,
        url: nil,
        date: nil,
        tags: []
      }

      # Handle table rows specially
      if container.name == "tr"
        return extract_table_row_data(container, base_url)
      end

      # Find the article link element (skip category/tag links)
      link_element = find_article_link_in_container(container, base_url)
      return data unless link_element

      href = link_element["href"]
      return data if href.blank?

      data[:url] = UrlUtils.resolve_url(href, base_url)
      data[:title] = extract_article_title(container, link_element)
      data[:date] = DateExtractor.extract_date_from_el(container, data[:url], base_url)
      data[:tags] = extract_tags(container)

      data
    end

    # Finds the main article link in a container, skipping category/tag links
    def find_article_link_in_container(container, base_url)
      # Compute base_path for excluding the current page
      base_path = UrlUtils.extract_path(base_url, base_url) || "/"

      # If container IS a link
      if container.name == "a"
        href = container["href"]
        path = UrlUtils.extract_path(href, base_url)
        return container if article_like_path?(path, base_path)
        return nil
      end

      # Check if parent is a link (common pattern: <a><article>...</article></a>)
      parent = container.parent
      if parent&.name == "a"
        href = parent["href"]
        path = UrlUtils.extract_path(href, base_url)
        return parent if article_like_path?(path, base_path)
      end

      # Look for links in headings first (most reliable for article title links)
      heading_link = container.css("h1 a[href], h2 a[href], h3 a[href], h4 a[href]").first
      if heading_link
        href = heading_link["href"]
        path = UrlUtils.extract_path(href, base_url)
        return heading_link if article_like_path?(path, base_path)
      end

      # Fall back to first article-like link
      container.css("a[href]").each do |link|
        href = link["href"]
        path = UrlUtils.extract_path(href, base_url)
        return link if article_like_path?(path, base_path)
      end

      nil
    end

    TITLE_CELL_SELECTORS = [ "td.title", 'td[class*="title"]' ]
    DATE_CELL_SELECTORS = [ "td.date", 'td[class*="date"]', "td#date" ]
    TAGS_CELL_SELECTORS = [ "td.tags", 'td[class*="tags"]' ]

    # Extracts data from a table row
    def extract_table_row_data(row, base_url)
      data = {
        title: nil,
        url: nil,
        date: nil,
        tags: []
      }

      title_cell = row.css(TITLE_CELL_SELECTORS.join(", ")).first
      date_cell = row.css(DATE_CELL_SELECTORS.join(", ")).first
      tags_cell = row.css(TAGS_CELL_SELECTORS.join(", ")).first

      # If title cell exists, it contains the link; otherwise,
      # fall back to the first article-like link in the row.
      link_element =
        if title_cell
          title_cell.css("a[href]").first
        else
          find_article_link_in_container(row, base_url)
        end

      if link_element
        href = link_element["href"]
        unless href.include?("/category/")
          data[:url] = UrlUtils.resolve_url(href, base_url)
          data[:title] = link_element.text.strip
        end
      end

      if data[:url]
        # Try date from URL first
        data[:date] = WebProcessor::DateExtractor.extract_date_from_url(data[:url], base_url)

        # Fall back to date cell
        if data[:date].nil? && date_cell
          date_text = date_cell.text.strip.gsub(/\u00A0/, " ").gsub(/\s+/, " ").strip
          data[:date] = DateUtils.parse_date(date_text) if date_text.present?
        end

        # Extract tags from tags cell
        if tags_cell
          tag_links = tags_cell.css("a[href]")
          data[:tags] = tag_links.map { |link| link.text.strip }.reject(&:empty?)
        end
      end

      data
    end

    # Sorts articles by date (oldest first)
    def sort_articles(articles)
      articles.each_with_index { |a, i| a[:original_index] = i }
      articles.sort_by do |article|
        [ article[:date] || Date.new(9999, 12, 31), article[:original_index] ]
      end
    end
  end
end
