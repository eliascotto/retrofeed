class WebProcessor
  class ArchiveExtractor
    include ArticleExtractor

    # Fast CSS selectors to try first (in priority order)
    FAST_SELECTORS = [
      # Semantic HTML5
      "article",
      "main article",

      # Links as containers (common pattern like mitchellh.com)
      # The link wraps a div that contains the article info
      "main div.flex-col > a[href]",
      ".divide-y > a[href]",

      # Common list patterns
      "ul.posts > li",
      "ul.post-archives > li",
      "ul.archive > li",
      "ul.articles > li",
      "ul.entries > li",
      "ul.post-list > li",
      "ol.posts > li",

      # Section-based
      "section.posts > article",
      "section.articles > article",

      # Generic list items in common containers
      ".posts li",
      ".post-list li",
      ".posts-list li",
      "#posts li",
      "#post-list li",
      "#posts-list li",
      ".archive li",
      ".articles li",

      # Table-based archives
      "table.archive tr",
      "table.posts tr",
      "table tr:has(td.title)",

      # Generic class-based (last resort for fast path)
      '[class*="post-item"]',
      '[class*="article-item"]',
      '[class*="blog-post"]'
    ].freeze

    # Extracts articles using hybrid approach:
    # 1. Fast CSS selectors (O(1) per selector)
    # 2. Pattern-based fallback (O(n) where n = links)
    # 3. Direct link extraction (last resort)
    #
    # @param doc [Nokogiri::HTML::Document] The HTML document
    # @param base_url [String] The base URL
    # @param debug [Boolean] When true, also compute the per-phase "what-if" trace
    # @return [Array<Hash>] Array of article hashes
    def self.extract_articles(doc, base_url, debug: false)
      new(doc, base_url).extract_articles(debug: debug)
    end

    def initialize(doc, base_url)
      @doc = doc
      @base_url = base_url
      # Compute base_path for excluding the current page from article links
      @base_path = UrlUtils.extract_path(base_url, base_url) || "/"
      # Apply custom rules to limit search scope for specific domains
      @search_container = ArchiveContainerExtractor.find_container(base_url, @doc) || @doc
    end

    # Extracts articles from the given document using a hybrid strategy.
    #
    # @param debug [Boolean] When true, populate the trace with the per-phase
    #   "what-if" comparison and the candidate containers considered. This runs
    #   every phase regardless of the winner, so it is opt-in and off by default.
    # @return [Hash] A hash containing the extracted articles and extraction trace.
    def extract_articles(debug: false)
      trace = ExtractionTrace.new(
        strategy: :hybrid,
        base_url: @base_url
      )

      # In debug mode, record the alternatives the extractor could have picked
      # before running the actual (unchanged) selection cascade below.
      if debug
        trace.container_candidates = ArchiveContainerExtractor.container_candidates(@base_url, @doc)
        trace.phase_results = compute_phase_results()
      end

      # Phase 1: Try fast CSS selectors
      containers, matched_selector = try_fast_selectors_with_info()
      if containers && containers.length >= 3
        articles = extract_and_validate(containers)
        if articles.length >= 3
          trace.phase = :try_fast_selectors_with_info
          trace.phase_detail = matched_selector
          trace.containers_count = containers.length
          return { articles: articles, trace: trace }
        end
      end

      # Phase 2: Pattern discovery fallback
      results = discover_pattern_from_links_with_info()
      if results && results.fetch(:containers, []).length >= 3
        articles = extract_and_validate(results.fetch(:containers, []))
        if articles.length >= 3
          trace.phase = :discover_pattern_from_links_with_info
          trace.phase_detail = results.fetch(:selector, {})
          trace.containers_count = results.fetch(:containers, []).length
          trace.article_like_links = results.fetch(:trace, [])
          trace.dropped_urls = dropped_url(trace.article_like_links, articles)
          return { articles: articles, trace: trace }
        end
      end

      # Phase 3: Last resort - direct link extraction
      results = extract_from_links_directly()
      articles = results.fetch(:articles, [])
      trace.phase = :extract_from_links_directly
      trace.article_like_links = results.fetch(:trace, [])
      trace.dropped_urls = dropped_url(trace.article_like_links, articles)
      { articles: articles, trace: trace }
    end

    private
      # Maximum ratio of article-like links to containers for a phase to be considered valid
      COLLAPSE_RATIO = 2

      # Debug-only: runs all three phases and reports each phase's would-be result
      # count, so the playground can show why a phase won. The "chosen" flag follows
      # the same rule as the production cascade above (first phase with >= 3
      # containers wins; direct-link extraction is the last resort), so exactly one
      # phase is marked and it always matches the real winner.
      #
      # @return [Array<Hash>] Per-phase summaries with keys :phase, :detail,
      #   :containers, :articles, :chosen
      def compute_phase_results
        fast_containers, fast_selector = try_fast_selectors_with_info()
        pattern = discover_pattern_from_links_with_info()
        pattern_containers = pattern ? pattern.fetch(:containers, []) : []
        direct = extract_from_links_directly()

        fast_articles    = fast_containers ? extract_and_validate(fast_containers) : []
        pattern_articles = pattern_containers.any? ? extract_and_validate(pattern_containers) : []

        fast_wins    = fast_articles.length >= 3
        pattern_wins = !fast_wins && pattern_articles.length >= 3
        direct_wins  = !fast_wins && !pattern_wins

        [
          {
            phase: :try_fast_selectors_with_info,
            detail: fast_selector,
            containers: fast_containers&.length,
            articles: fast_articles.length,
            chosen: !!fast_wins
          },
          {
            phase: :discover_pattern_from_links_with_info,
            detail: pattern&.fetch(:selector, nil),
            containers: pattern_containers.length,
            articles: pattern_articles.length,
            chosen: pattern_wins
          },
          {
            phase: :extract_from_links_directly,
            detail: nil,
            containers: nil,
            articles: direct.fetch(:articles, []).length,
            chosen: direct_wins
          }
        ]
      end

      # Phase 1: Try fast CSS selectors (returns containers and matched selector)
      def try_fast_selectors_with_info
        FAST_SELECTORS.each do |selector|
          begin
            containers = @search_container.css(selector)
            next if containers.empty?

            # Validate: must have article-like links
            valid_containers = containers.select { |c| has_article_link?(c) }

            # Return if we found enough valid containers
            if valid_containers.length >= 3
              return [ valid_containers, selector ]
            end
          rescue Nokogiri::CSS::SyntaxError
            # Skip invalid selectors
            next
          end
        end

        [ nil, nil ]
      end

      # Checks if a container has an article-like link
      def has_article_link?(container)
        # If container is itself a link
        if container.name == "a"
          href = container["href"]
          return false if href.blank?
          path = UrlUtils.extract_path(href, @base_url)
          return article_like_path?(path, @base_path)
        end

        # Check if parent is a link (common pattern: <a><article>...</article></a>)
        parent = container.parent
        if parent&.name == "a"
          href = parent["href"]
          if href.present?
            path = UrlUtils.extract_path(href, @base_url)
            return article_like_path?(path, @base_path)
          end
        end

        # Look for link inside container
        link = container.css("a[href]").first
        return false unless link

        href = link["href"]
        return false if href.blank?

        path = UrlUtils.extract_path(href, @base_url)
        article_like_path?(path, @base_path)
      end

      # Phase 2: Pattern discovery from sampling links (returns containers and pattern info)
      def discover_pattern_from_links_with_info
        # Find all article-like links (use @search_container which may be limited by custom rules)
        articles_links_res = find_article_links_with_trace(@search_container, @base_url)
        article_links = articles_links_res.fetch(:articles, [])
        trace = articles_links_res.fetch(:trace, [])
        return nil if article_links.length < 3

        # Sample first 20 links for pattern discovery
        sample_links = article_links.first(20)

        # Find parent patterns
        parent_patterns = analyze_parent_patterns(sample_links)
        return nil if parent_patterns.empty?

        # Get the most common pattern
        best_pattern = parent_patterns.max_by { |p| p[:count] }
        return nil unless best_pattern && best_pattern[:count] >= 3

        # Use the pattern to find ALL matching containers
        containers = find_all_matching_containers(best_pattern)
        return nil if containers.blank?
        return nil if pattern_collapses?(containers, article_links)
        {
          containers: containers,
          selector: best_pattern[:selector],
          trace: trace
        }
      end

      # A real per-item pattern wraps roughly one article link per container. When the
      # matched containers hold far more article links than there are containers (e.g.
      # a flat list of <a> siblings under a shared <section>), the pattern is degenerate
      # and would collapse N articles down to one-per-container. Reject it so the
      # cascade falls through to direct link extraction.
      def pattern_collapses?(containers, article_links)
        links_in_containers = containers.sum { |c| count_article_links(c) }
        links_in_containers > containers.length * COLLAPSE_RATIO
      end

      # Counts the number of article-like links in a container
      def count_article_links(container)
        container.css("a[href]").select { |a| article_like_path?(a[:href], @base_url) }.length
      end

      # Returns URLs of article-like links that were excluded during extraction
      def dropped_url(article_like_links, articles)
        return [] if article_like_links.blank?
        kept = articles.map { |a| a[:url] }
        article_like_links.select { |e| e[:included] }.map { |e| e[:url] }.compact - kept
      end

      # Analyzes parent patterns from sample links
      def analyze_parent_patterns(links)
        patterns = Hash.new { |h, k| h[k] = { selector: k, count: 0, sample: nil } }

        links.each do |link|
          # Get container (immediate parent or grandparent)
          container = find_container_for_link(link)
          next unless container

          # Build selector pattern
          selector = build_selector_pattern(container)
          next unless selector

          patterns[selector][:count] += 1
          patterns[selector][:sample] ||= container
        end

        patterns.values.select { |p| p[:count] >= 2 }
      end

      # Finds the container for a link (O(1) - only checks parent and grandparent)
      def find_container_for_link(link)
        parent = link.parent
        return nil unless parent&.element?

        # Skip if parent is body/html
        return nil if %w[body html].include?(parent.name)

        # If parent is good container, use it
        return parent if good_container?(parent)

        # Try grandparent
        grandparent = parent.parent
        return grandparent if grandparent&.element? && good_container?(grandparent)

        # Use parent as fallback (but not if it's too generic)
        parent unless %w[div span].include?(parent.name) && parent["class"].blank?
      end

      # Checks if an element is a good article container
      def good_container?(element)
        return false unless element

        tag = element.name

        # Good semantic containers
        return true if %w[article li section tr].include?(tag)
        return true if element["role"] == "article"

        # Has article-like classes
        classes = element["class"] || ""
        return true if classes.match?(/post|article|entry|item|blog/i)

        # Div with heading or time is acceptable
        if tag == "div"
          return element.css("h1, h2, h3, h4, time").any?
        end

        false
      end

      # Builds a CSS selector pattern from a container
      def build_selector_pattern(container)
        tag = container.name
        classes = (container["class"] || "").split(/\s+/)
        parent = container.parent

        # Find the most specific class
        specific_class = classes.find { |c| c.match?(/post|article|entry|item|blog/i) }
        specific_class ||= classes.first if classes.length == 1

        parts = []

        # Add parent context if meaningful
        if parent&.element? && !%w[body html].include?(parent.name)
          parent_classes = (parent["class"] || "").split(/\s+/)
          parent_specific = parent_classes.find { |c| c.match?(/posts|articles|archive|list|entries/i) }

          if parent_specific
            parts << "#{parent.name}.#{parent_specific}"
          elsif parent.name == "ul" || parent.name == "ol"
            parts << parent.name
          end
        end

        # Build container part
        if specific_class
          parts << "#{tag}.#{specific_class}"
        else
          parts << tag
        end

        parts.join(" > ")
      end

      # Finds all containers matching the discovered pattern
      def find_all_matching_containers(pattern)
        begin
          containers = @search_container.css(pattern[:selector])
          # Filter to only those with article links
          containers.select { |c| has_article_link?(c) }
        rescue Nokogiri::CSS::SyntaxError
          # If selector is invalid, return sample-based containers
          nil
        end
      end

      # Phase 3: Extract directly from links (last resort)
      def extract_from_links_directly
        articles_links_res = find_article_links_with_trace(@search_container, @base_url)
        article_links = articles_links_res.fetch(:articles, [])
        trace = articles_links_res.fetch(:trace, [])
        return {} if article_links.empty?

        articles = article_links.map do |link|
          # Try to get context from parent
          parent = link.parent
          title = extract_title_from_link(link)
          date = extract_date_for_link(link, parent)

          {
            title: title,
            url: UrlUtils.resolve_url(link["href"], @base_url),
            date: date,
            tags: []
          }
        end

        articles = articles.select { |a| a[:url] && a[:title].present? }
        articles = articles.uniq { |a| a[:url] }
        sorted = sort_articles(articles)
        { articles: sorted, trace: trace }
      end

      # Extracts title from a link
      def extract_title_from_link(link)
        # Try link text first
        text = link.text.strip
        return text if text.present? && text.length > 2

        # Try title attribute
        title = link["title"]
        return title.strip if title.present?

        # Try aria-label
        label = link["aria-label"]
        return label.strip if label.present?

        nil
      end

      # Extracts date for a link
      def extract_date_for_link(link, parent)
        # Try sibling or parent time element
        if parent
          time_elem = parent.css("time").first
          if time_elem
            datetime = time_elem["datetime"] || time_elem.text.strip
            parsed = DateUtils.parse_date(datetime)
            return parsed if parsed
          end
        end

        # Try extracting from URL
        WebProcessor::DateExtractor.extract_date_from_url(link["href"], @base_url)
      end

      # Extracts and validates articles from containers
      def extract_and_validate(containers)
        return [] if containers.nil? || containers.empty?
        articles = containers.map do |container|
          extract_article_data(container, @base_url)
        end

        # Filter valid articles
        articles = articles.select { |a| a[:url] }
        articles = articles.uniq { |a| a[:url] }

        sort_articles(articles)
      end
  end
end
