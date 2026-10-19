class WebProcessor
  class InvalidArchiveError < StandardError; end

  # === Interval Configuration ===
  # All intervals are configured in config/initializers/web_processor.rb

  # Time between full archive re-crawls (discover new articles)
  def self.archive_interval
    @archive_interval || 14.days
  end

  # Hard minimum between website re-crawls (for manual refresh rate limiting)
  def self.archive_min_interval
    @archive_min_interval || 60.minutes
  end

  # Time between article content re-checks (update existing articles)
  def self.content_interval
    @content_interval || 60.days
  end

  # Hard minimum between article refreshes (for manual refresh rate limiting)
  def self.content_min_interval
    @content_min_interval || 30.minutes
  end

  # Legacy accessors for backward compatibility
  def self.update_interval
    @update_interval || archive_interval
  end

  def self.refresh_interval
    @refresh_interval || content_min_interval
  end

  # Determines if an article's content should be updated
  # Returns true if:
  # - Article is new (not yet saved)
  # - Article has no content
  # - Article hasn't been fetched within content_interval
  #
  # @param article [Article] The article to check
  # @param force [Boolean] If true, only check minimum interval (for manual refresh)
  # @return [Boolean] true if content should be fetched/updated
  def self.should_update_content?(article, force: false)
    return true if article.nil? || article.new_record? || article.content_html.blank?

    last_fetched = article.last_content_fetched_at || article.updated_at
    if force
      # For manual refresh, only enforce the hard minimum
      last_fetched < content_min_interval.ago
    else
      # For automatic refresh, use the longer content interval
      last_fetched < content_interval.ago
    end
  end

  # Determines if a website's archive should be re-crawled
  # Returns true if:
  # - Website is new (no last_crawled_at)
  # - Website hasn't been crawled within archive_interval
  #
  # @param website [Website] The website to check
  # @param force [Boolean] If true, only check minimum interval (for manual refresh)
  # @return [Boolean] true if archive should be crawled
  def self.should_crawl_archive?(website, force: false)
    return true if website.nil? || website.last_crawled_at.nil?

    if force
      # For manual refresh, only enforce the hard minimum
      website.last_crawled_at < archive_min_interval.ago
    else
      # For automatic refresh, use the longer archive interval
      website.last_crawled_at < archive_interval.ago
    end
  end

  # Updates article content using defuddle
  # This method bypasses the update interval check and can be called directly
  #
  # @param article [Article] The article to update
  # @param article_data [Hash] Hash with article metadata from archive extraction
  # @return [Article] The updated article (not saved)
  def self.update_article_content(article, article_data)
    if self.should_update_content?(article)
      result = extract_article_content(article_data[:url])
      if result && result[:content]
        content = result[:content]
        raw_title = content[:title] || article_data[:title]
        article.title = TitleCleaner.clean_article_title(raw_title, article)
        article.content_html = content[:content_html]
        article.content_md = content[:content_md]
        article.word_count = content[:word_count]
        article.publication_date = content[:published]
      else
        # Content extraction failed - keep existing title or use article_data title
        if article.title.blank?
          article.title = TitleCleaner.clean_article_title(article_data[:title], article)
        end
        if result && result[:error]
          Rails.logger.warn("[WebProcessor] Failed to extract content for #{article_data[:url]}: #{result[:error]}")
        end
      end
      article
    else
      article
    end
  end

  # Extracts article content using defuddle via HTTP (Node.js extractor server)
  # Returns metadata, HTML content, and Markdown content
  #
  # In mock mode (MOCK_WEB_DATA=true), attempts to use fixture HTML if available.
  # Falls back to live fetching if no fixture exists.
  #
  # @param url [String] The URL of the article to extract
  # @param html [String, nil] Optional pre-fetched HTML content (avoids double fetch)
  # @return [Hash] Hash with either:
  #   - :content key containing article data (on success)
  #   - :error key containing error message (on failure)
  def self.extract_article_content(url, html: nil)
    Rails.logger.info("[WebProcessor] Starting article extraction for: #{url}")

    start_time = Time.current

    # Determine HTML source
    html_source = html
    if html_source
      Rails.logger.info("[WebProcessor] Using pre-fetched HTML (#{html_source.length} bytes)")
    elsif WebFetcher.mock_mode?
      # In mock mode, try to load fixture HTML
      fixture_path = WebFetcher::Mock.find_fixture_for_url(url)
      if fixture_path && File.exist?(fixture_path)
        Rails.logger.info("[WebProcessor] Using mock HTML from: #{fixture_path}")
        html_source = File.binread(fixture_path)
      else
        Rails.logger.info("[WebProcessor] No mock fixture found, fetching live")
        # Use Ruby-fetch to improve date extraction
        html_source, doc = live_fetch_webpage(url)
      end
    else
      Rails.logger.info("[WebProcessor] No html provided and not in mock mode, fetching live")
      # Use Ruby-fetch to improve date extraction
      html_source, doc = live_fetch_webpage(url)
    end

    if doc.present?
      Rails.logger.info("[WebProcessor] Document parsed successfully")
    else
      Rails.logger.warn("[WebProcessor] No document available for date extraction")
    end

    # Call extractor server via HTTP
    result = ExtractorClient.extract(url: url, html: html_source)

    elapsed = ((Time.current - start_time) * 1000).round(2)
    Rails.logger.info("[WebProcessor] Defuddle completed in #{elapsed}ms")

    # Handle error response
    if result[:error]
      Rails.logger.error("[WebProcessor] Defuddle error for #{url}: #{result[:error]}")
      return { error: result[:error] }
    end

    word_count = result[:wordCount] || 0
    html_length = result[:contentHtml]&.length || 0
    md_length = result[:contentMd]&.length || 0
    author = WebProcessor::AuthorExtractor.extract_author(url, doc, result)

    unless doc.present?
      # Published is the value from defuddle which is currently less reliable than our internal parsing process
      Rails.logger.warn("[WebProcessor] No document available for date extraction from article: #{url}")
      published = DateUtils.parse_date(result[:published])
      return {
        content: {
          title: result[:title],
          author: author,
          content_html: result[:contentHtml],
          content_md: result[:contentMd],
          word_count: result[:wordCount],
          published: published
        }
      }
    end

    # Extract date from document
    date_extractor_result = DateExtractor.extract_date(doc, url, url)

    if date_extractor_result.present?
      Rails.logger.info("[WebProcessor] Date extracted from article: #{url}")
      published = date_extractor_result
    else
      Rails.logger.warn("[WebProcessor] No date extracted from article: #{url}")
      published = DateUtils.parse_date(result[:published])
    end

    Rails.logger.info("[WebProcessor] Content extracted: #{word_count} words, HTML: #{html_length} chars, Markdown: #{md_length} chars")

    {
      content: {
        title: result[:title],
        author: author,
        content_html: result[:contentHtml],
        content_md: result[:contentMd],
        word_count: result[:wordCount],
        published: published
      }
    }
  rescue ExtractorClient::ConnectionError => e
    Rails.logger.error("[WebProcessor] Extractor connection error for #{url}: #{e.message}")
    { error: "Extractor unavailable: #{e.message}" }
  rescue ExtractorClient::TimeoutError => e
    Rails.logger.error("[WebProcessor] Extractor timeout for #{url}: #{e.message}")
    { error: "Extractor timeout: #{e.message}" }
  rescue ExtractorClient::ExtractorError => e
    Rails.logger.error("[WebProcessor] Extractor error for #{url}: #{e.message}")
    { error: e.message }
  end

  # Determines if a webpage contains a valid archive
  # An archive is defined as a series of local links with similar path patterns
  #
  # @param html [Nokogiri::HTML::Document] The parsed HTML document
  # @param base_url [String] The base URL of the page
  # @param min_links [Integer] Minimum number of similar links to consider it an archive (default: 5)
  # @return [Boolean] true if the page appears to be an archive
  def self.contains_valid_archive?(html, base_url, min_links: 5)
    contains_valid_archive_with_reason?(html, base_url, min_links: min_links).valid?
  end

  # Same decision as contains_valid_archive?, but returns an ArchiveVerdict carrying
  # the link counts behind the verdict so callers (the playground) can explain why a
  # page was accepted or rejected. All three checks are always computed so the verdict
  # is complete; the boolean predicate above just reads .valid?.
  #
  # "Is this link an article?" is decided by ArticleExtractor.article_like_path? -- the
  # same predicate extraction uses -- so validation and extraction can't disagree.
  #
  # @param html [Nokogiri::HTML::Document] The parsed HTML document
  # @param base_url [String] The base URL of the page
  # @param min_links [Integer] Minimum number of similar links to consider it an archive (default: 5)
  # @return [ArchiveVerdict]
  def self.contains_valid_archive_with_reason?(html, base_url, min_links: 5)
    base_path = UrlUtils.extract_path(base_url, base_url) || "/"

    # Extract all links from the page
    links = html.css("a[href]").map { |link| link["href"] }.compact

    # Filter for local links (same domain)
    local_links = links.select { |link| UrlUtils.is_local_link?(link, base_url) }

    # Normalize all links to absolute URLs and extract paths, dropping the current
    # page and the bare root.
    candidate_paths = local_links
      .map { |link| UrlUtils.extract_path(link, base_url) }
      .compact
      .reject { |path| path == base_path || path == "/" }

    # Keep only article-like paths, using the same predicate as extraction so the two
    # steps share one exclusion list (categories, tags, feeds, /_next, etc.).
    article_paths = candidate_paths.select { |path| ArticleExtractor.article_like_path?(path, base_path) }

    # Check 1: many flat article links (for sites like overreacted.io where each
    # article has a unique flat path).
    article_like_count = article_paths.length

    # Check 2: date-based URLs (e.g. /2024/01/15/slug, /posts/2024-01-15-slug,
    # /15-01-2024/slug). Delegates to the shared URL date parser so detection and
    # extraction recognize the same set of formats, including month-level and
    # regional day/month-first layouts.
    date_paths_count = article_paths.count { |path| WebProcessor::DateExtractor.extract_date_from_path(path) }

    # Check 3: group paths by their directory pattern (path minus the last segment).
    # For example: /posts/2024/01/article and /posts/2024/02/article share /posts/2024/*.
    pattern_counts = article_paths
      .group_by { |path| directory_pattern_for(path) }
      .transform_values(&:count)
    top_pattern, top_pattern_count = pattern_counts.max_by { |_pattern, count| count } || [ nil, 0 ]

    passed_check =
      if article_like_count >= min_links
        :article_like
      elsif date_paths_count >= min_links
        :date_paths
      elsif top_pattern_count >= min_links
        :pattern
      else
        nil
      end

    Rails.logger.debug { "[ContainsValidArchive?] #{base_url} is #{passed_check.nil? ? 'invalid' : 'valid'}" }

    ArchiveVerdict.new(
      base_url: base_url,
      min_links: min_links,
      valid: !passed_check.nil?,
      local_links_count: local_links.length,
      candidate_paths_count: candidate_paths.length,
      article_like_count: article_like_count,
      date_paths_count: date_paths_count,
      top_pattern: top_pattern,
      top_pattern_count: top_pattern_count,
      passed_check: passed_check
    )
  end

  # Returns the directory pattern of a path: the path minus its last segment
  # (the article slug). /posts/2024/01/article -> /posts/2024/01. A single-segment
  # path is its own pattern.
  def self.directory_pattern_for(path)
    segments = path.split("/").reject(&:empty?)
    if segments.length >= 2
      "/" + segments[0..-2].join("/")
    else
      path
    end
  end

  # Extracts article information from an archive page
  # Also checks for custom detectors that override extraction for specific domains
  #
  # @param html [Nokogiri::HTML::Document] The parsed HTML document
  # @param base_url [String] The base URL of the page
  # @param debug [Boolean] When true, the hybrid extractor also records the
  #   per-phase "what-if" comparison and candidate containers in the trace
  # @return [Array<Hash>] Array of hashes with keys: :title, :url, :date, :tags
  def self.extract_articles_from_archive(html, base_url, debug: false)
    # Check for custom detector that handles extraction
    custom_extr_result = try_custom_extraction(html, base_url)
    if custom_extr_result
      return custom_extr_result
    end

    start_time = Time.current
    extraction_result = ArchiveExtractor.extract_articles(html, base_url, debug: debug)
    elapsed = ((Time.current - start_time) * 1000).round(2)

    Rails.logger.debug { "[WebProcessor] Extracted #{extraction_result[:articles].length} articles (#{elapsed}ms)" }

    extraction_result
  end

  # Attempts to use a custom detector for article extraction
  #
  # @param html [Nokogiri::HTML::Document] The parsed HTML document
  # @param base_url [String] The base URL of the page
  # @return [Hash, nil] Hash of articles and trace if custom detector found and handles extraction, nil otherwise
  def self.try_custom_extraction(html, base_url)
    detector_class = SiteProfile.for(base_url)&.detector
    return nil unless detector_class

    begin
      detector = detector_class.new(base_url)
      return nil unless detector.handles_extraction?

      trace = ExtractionTrace.new(
        strategy: :custom,
        phase: :extract_articles,
        phase_detail: detector_class.name,
        base_url: base_url,
        base_path: base_url)
      Rails.logger.info("[WebProcessor] Using custom extraction from: #{detector_class.name}")

      start_time = Time.current
      articles = detector.extract_articles(html, base_url)
      elapsed = ((Time.current - start_time) * 1000).round(2)

      Rails.logger.info("[WebProcessor] Custom extraction found #{articles.length} articles (#{elapsed}ms)")
      { articles: articles, trace: trace }
    rescue StandardError => e
      Rails.logger.warn("[WebProcessor] Custom extraction failed: #{e.message}, falling back to default strategy")
      nil
    end
  end

  TITLE_DELIMITERS = [ "|", "-", "–", "—" ].freeze
  # Extracts the title of a website from the HTML.
  # If not title in index page, use title from archive page.
  # Takes care or removing the domain and any delimiters from the title.
  #
  # @param index_html [Nokogiri::HTML::Document] The parsed HTML document of the website index page
  # @param html [Nokogiri::HTML::Document] The parsed HTML document
  # @param base_url [String] The base URL of the page
  # @return [String, nil] The title of the website, or nil if no title is found
  def self.extract_website_title(index_html, archive_html, base_url)
    domain = UrlUtils.extract_domain(base_url)

    # Index page could not be present when using mocks
    if index_html.present?
      # Extract title from index page, then remove the domain and common delimiters
      index_title = index_html&.at_css("title")&.text&.strip
      if index_title.present?
        cleaned_index_title = index_title.remove(domain)
        TITLE_DELIMITERS.each do |delimiter|
          cleaned_index_title = cleaned_index_title.remove(delimiter)
        end
        return cleaned_index_title.strip if cleaned_index_title.present?
      end
    end

    # If no usable title in index page, use title from archive page
    archive_title = archive_html&.at_css("title")&.text&.strip
    if archive_title.blank?
      Rails.logger.warn("[WebProcessor] No <title> found for website (base_url: #{base_url})")
      return nil
    end

    cleaned_archive_title = archive_title.remove(domain)
    TITLE_DELIMITERS.each do |delimiter|
      cleaned_archive_title = cleaned_archive_title.remove(delimiter)
    end
    cleaned_archive_title.strip.presence
  end

  # Detects and stores a common title suffix pattern for a website
  #
  # Analyzes article titles from defuddle (articles with content) to find a common suffix
  # pattern (e.g., " — overreacted") and stores it for future title cleaning.
  # This uses titles from articles that have been fully processed (have content_html or content_md),
  # as these titles include the website name that needs to be removed.
  #
  # @param website [Website] The website to analyze
  # @return [String, nil] The detected suffix pattern, or nil if none found
  def self.detect_and_store_title_suffix(website)
    return nil if website.nil?

    # Get titles from articles that have been fully processed (have content from defuddle)
    # These titles include the website name suffix that needs to be cleaned
    titles = website.articles
                     .where("content_html IS NOT NULL AND content_html != '' OR content_md IS NOT NULL AND content_md != ''")
                     .where.not(title: [ nil, "" ])
                     .order(created_at: :desc)
                     .limit(50)
                     .pluck(:title)

    return nil if titles.length < 5

    # Detect common suffix
    suffix_pattern = TitleCleaner.detect_common_suffix(titles)

    if suffix_pattern.present?
      Rails.logger.info("[WebProcessor] Detected title suffix pattern for #{website.name || website.domain}: '#{suffix_pattern}'")
      old_pattern = website.title_suffix_pattern
      website.update(title_suffix_pattern: suffix_pattern)

      # If pattern changed, re-clean all article titles
      if old_pattern != suffix_pattern
        Rails.logger.info("[WebProcessor] Title suffix pattern changed, re-cleaning all article titles for #{website.name || website.domain}")
        reclean_article_titles(website)
      end

      suffix_pattern
    else
      Rails.logger.debug("[WebProcessor] No common title suffix pattern detected for #{website.name || website.domain}")
      nil
    end
  end

  # Re-cleans all article titles for a website using the current suffix pattern
  #
  # @param website [Website] The website whose articles to re-clean
  # @return [Integer] Number of titles updated
  def self.reclean_article_titles(website)
    return 0 if website.nil? || website.title_suffix_pattern.blank?

    updated_count = 0
    website.articles.find_each do |article|
      next if article.title.blank?

      cleaned_title = TitleCleaner.clean_article_title(article.title, article)
      if cleaned_title != article.title
        article.update_column(:title, cleaned_title)
        updated_count += 1
      end
    end

    Rails.logger.info("[WebProcessor] Re-cleaned #{updated_count} article titles for #{website.name || website.domain}")
    updated_count
  end

  private
    def self.live_fetch_webpage(url)
      results = WebFetcher.fetch(url, no_mock: true)
      html_source = results[:content]

      unless html_source
        Rails.logger.error("[WebProcessor] Failed to fetch HTML for #{url}")
        return [ nil, nil ]
      end

      Rails.logger.debug("[WebProcessor] Fetched HTML for #{url}: #{html_source.class} #{html_source.length} bytes")
      doc = Nokogiri::HTML(html_source)
      Rails.logger.info("[WebProcessor] Using live HTML (#{html_source.length} bytes)")
      [ html_source, doc ]
    rescue WebFetcher::FetchError => e
      Rails.logger.error("[WebProcessor] Failed to fetch HTML for #{url}: #{e.message}")
      [ nil, nil ]
    end
end

# Load modules after class definition
require_relative "web_processor/article_extractor"
require_relative "web_processor/title_cleaner"
