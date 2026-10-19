# Detects the archive page for a website
#
# Given a URL (which may be a homepage or an archive page), this service
# determines the best archive page URL using multiple detection strategies:
#
# 1. Validate user-provided URL (if it contains valid archive content)
# 2. Probe known archive paths (/archive, /blog, /posts, etc.)
# 3. Analyze links from the origin page to find archive-like pages
# 4. Use RSS/Atom feeds to confirm archive candidates (optional)
#
# Usage:
#   result = ArchivePageDetector.detect("https://example.com/blog")
#   result[:url]                # => "https://example.com/blog"
#   result[:method]             # => "user_provided"
#   result[:confidence_score]   # => 1.0
#   result[:pagination_detected] # => false
#
class ArchivePageDetector
  class DetectionError < StandardError; end

  # Result struct for detection output
  Result = Struct.new(
    :url,
    :method,
    :confidence_score,
    :pagination_detected,
    :notes,
    keyword_init: true
  )

  # Words commonly used for archive pages (ordered by priority!)
  # They might also come combined (e.g. /blog/all/)
  KNOWN_ARCHIVE_WORDS = %w[
    archive
    archives
    blog
    posts
    articles
    writing
    essays
    notes
    all
  ].freeze

  # Removed All since it's too generic
  KNOWN_ARCHIVE_LINK_TEXT = KNOWN_ARCHIVE_WORDS - %w[all]

  # Word-boundary match for archive keywords in link text, so "Call"/"Fall"/"install"
  # do not match. Built from KNOWN_ARCHIVE_LINK_TEXT so candidate finding and scoring
  # share one definition.
  ARCHIVE_LINK_TEXT_PATTERN = /\b(?:#{Regexp.union(KNOWN_ARCHIVE_LINK_TEXT).source})\b/i

  # Minimum candidate score required to displace a homepage that is itself a valid
  # archive, when the candidate's URL path carries no archive keyword.
  STRONG_CANDIDATE_SCORE = 0.6

  # Pagination indicator patterns in URLs
  PAGINATION_PATTERNS = [
    /\/page\/\d+/,           # /page/2
    /[?&]page=\d+/,          # ?page=2
    /[?&]p=\d+/,             # ?p=2
    /[?&]paged=\d+/,         # ?paged=2
    /[?&]offset=\d+/,        # ?offset=20
    /[?&]start=\d+/,         # ?start=10
    /[?&]after=[^&]+/,       # ?after=abc123 (cursor-based)
    /[?&]cursor=[^&]+/       # ?cursor=xyz (cursor-based)
  ].freeze

  # Link text patterns that indicate pagination
  PAGINATION_TEXT_PATTERNS = [
    /\Anext\z/i,
    /\Aolder\s*(posts|entries)?\z/i,
    /\Aprevious\s*(posts|entries)?\z/i,
    /\Anewer\s*(posts|entries)?\z/i,
    /\Aload\s*more\z/i,
    /^>+$/,
    /^>>$/,
    /^\u2192$/,              # right arrow
    /^\u00BB$/               # >>
  ].freeze

  # Detects the archive page for a given URL
  #
  # @param url [String] The URL to analyze (could be homepage or archive)
  # @param fetcher [#fetch, #head] The fetcher backend (defaults to live WebFetcher;
  #   the playground injects WebFetcher::Playground for fixture caching)
  # @return [Result] Detection result with url, method, confidence, pagination, notes
  # @raise [DetectionError] If no archive page can be found
  def self.detect(url, fetcher: WebFetcher)
    new(url, fetcher: fetcher).detect
  end

  def initialize(url, fetcher: WebFetcher)
    @user_url = UrlUtils.validate_and_normalize_url(url)
    @origin = URI.parse(@user_url).origin
    @candidates = []
    @fetcher = fetcher
  end

  # Detects the archive page for a given URL
  #
  # @return [Result] Detection result struct with url, method, confidence, pagination, notes
  # @raise [DetectionError] If no archive page can be found
  def detect
    Rails.logger.info("[ArchivePageDetector] Starting detection for: #{@user_url}")

    # Strategy 0: Check for custom detector in registry
    result = try_custom_detector
    return result if result

    # Strategy A: Check if user-provided URL is already a valid archive
    result = try_user_provided_url
    return result if result

    # Strategy B: Probe known archive paths
    result = try_known_paths
    return result if result

    # Strategy C: Analyze links from origin page
    result = try_link_analysis
    return result if result

    # Strategy D: Try feed-assisted discovery (last resort)
    result = try_feed_assisted
    return result if result

    # No archive found
    Rails.logger.warn("[ArchivePageDetector] No archive page found for #{@origin}")
    raise DetectionError, "Could not detect an archive page for this website"
  end

  private
    # Strategy 0: Check registry for known archive URL or custom detector
    #
    # First checks for a known archive URL (simple domain -> URL mapping).
    # If not found, checks for a custom detector class.
    #
    # @return [Result, nil] Result if found, nil otherwise
    def try_custom_detector
      # Check for known archive URL first (fastest path)
      result = try_known_archive
      return result if result

      # Fall back to custom detector class
      try_detector_class
    end

    # Checks for a known archive URL in the registry
    #
    # @return [Result, nil] Result if known archive found, nil otherwise
    def try_known_archive
      known_url = SiteProfile.for(@user_url)&.archive_url
      return nil unless known_url

      Rails.logger.info("[ArchivePageDetector] Using known archive URL: #{known_url}")

      # Verify the known URL is accessible and valid
      result = fetch_and_parse(known_url)
      unless result
        Rails.logger.warn("[ArchivePageDetector] Known archive URL not accessible: #{known_url}")
        log_decision(strategy: "known_archive", candidate_url: known_url, accepted: false, reason: "Known archive URL not accessible")
        return nil
      end

      html, final_url = result
      pagination = detect_pagination(html)

      log_decision(strategy: "known_archive", candidate_url: final_url, accepted: true, reason: "Known archive URL from registry", score: 1.0)

      Result.new(
        url: final_url,
        method: "known_archive",
        confidence_score: 1.0,
        pagination_detected: pagination,
        notes: "Known archive URL from registry"
      )
    end

    # Checks for a custom detector class in the registry
    #
    # @return [Result, nil] Result if detector found and succeeds, nil otherwise
    def try_detector_class
      detector_class = SiteProfile.for(@user_url)&.detector
      return nil unless detector_class

      Rails.logger.info("[ArchivePageDetector] Using custom detector: #{detector_class.name}")

      begin
        detector = detector_class.new(@user_url, fetcher: @fetcher)
        result = detector.detect
        Rails.logger.info("[ArchivePageDetector] Custom detector returned: #{result&.url}")
        result
      rescue StandardError => e
        Rails.logger.warn("[ArchivePageDetector] Custom detector failed: #{e.message}, falling back to default strategies")
        nil
      end
    end

    # Strategy A: Check if user-provided URL is a valid archive
    #
    # Skips validation when the user provides the homepage URL, since we want to
    # check dedicated archive paths first (e.g., /blog, /archive). This prevents
    # incorrectly treating a homepage with some article links as the full archive
    # when a dedicated archive page exists.
    #
    # @return [Result, nil] Result if valid, nil otherwise
    def try_user_provided_url
      Rails.logger.info("[ArchivePageDetector] Trying user-provided URL: #{@user_url}")

      # Skip if user provided the homepage - we should check known paths first
      # to prefer dedicated archive pages over homepages with some articles
      if normalize_path(@user_url) == normalize_path(@origin) || @user_url == @origin
        Rails.logger.info("[ArchivePageDetector] User provided homepage, checking known paths first")
        log_decision(strategy: "user_provided", candidate_url: @user_url, accepted: false, reason: "User provided homepage; checking known paths first")
        return nil
      end

      result = fetch_and_parse(@user_url)
      unless result
        log_decision(strategy: "user_provided", candidate_url: @user_url, accepted: false, reason: "Fetch failed")
        return nil
      end

      html, final_url = result

      if WebProcessor.contains_valid_archive?(html, final_url, min_links: 1)
        pagination = detect_pagination(html)
        Rails.logger.info("[ArchivePageDetector] User URL is valid archive (pagination: #{pagination})")
        log_decision(strategy: "user_provided", candidate_url: final_url, accepted: true, reason: "User-provided URL validated as archive", score: 1.0)

        return Result.new(
          url: final_url,
          method: "user_provided",
          confidence_score: 1.0,
          pagination_detected: pagination,
          notes: "User-provided URL validated as archive"
        )
      end

      Rails.logger.info("[ArchivePageDetector] User URL is not a valid archive, trying other strategies")
      log_decision(strategy: "user_provided", candidate_url: final_url, accepted: false, reason: "Not a valid archive")
      nil
    end

    # Strategy B: Probe known archive paths
    #
    # Tracks final URLs after redirects to handle cases like /blog redirecting to /blog/
    #
    # @return [Result, nil] Result if found, nil otherwise
    def try_known_paths
      Rails.logger.info("[ArchivePageDetector] Probing known archive paths...")

      # Try bare paths first, then .html variants for older sites
      KNOWN_ARCHIVE_WORDS.each do |word|
        [ "/#{word}", "/#{word}.html" ].each do |candidate_path|
          result = try_known_path(candidate_path)
          return result if result
        end
      end

      nil
    end

    def try_known_path(path)
      candidate_url = "#{@origin}#{path}"
      return nil if normalize_path(candidate_url) == normalize_path(@user_url)

      # HEAD first to confirm the path exists and follow any redirects (e.g., /blog -> /blog/)
      head_result = safe_head(candidate_url)
      unless head_result && (200..299).cover?(head_result[:status])
        log_decision(strategy: "known_path", candidate_url: candidate_url, accepted: false, reason: "HEAD returned non-2xx or failed")
        return nil
      end

      fetch_url = head_result[:final_url] || candidate_url
      result = fetch_and_parse(fetch_url)
      unless result
        log_decision(strategy: "known_path", candidate_url: fetch_url, accepted: false, reason: "Fetch failed")
        return nil
      end

      html, final_url = result
      unless WebProcessor.contains_valid_archive?(html, final_url, min_links: 1)
        log_decision(strategy: "known_path", candidate_url: final_url, accepted: false, reason: "Not a valid archive")
        return nil
      end

      pagination = detect_pagination(html)
      Rails.logger.info("[ArchivePageDetector] Found archive at known path: #{path} -> #{final_url} (pagination: #{pagination})")
      log_decision(strategy: "known_path", candidate_url: final_url, accepted: true, reason: "Found at known path: #{path}", score: 0.9)

      Result.new(
        url: final_url,
        method: "known_path",
        confidence_score: 0.9,
        pagination_detected: pagination,
        notes: "Found at known path: #{path}"
      )
    end

    # Strategy C: Analyze links from origin page
    #
    # Checks dedicated archive pages first (e.g., /blog, /archive), then falls
    # back to the homepage if no dedicated archive is found. This ensures we
    # prefer pages explicitly intended as archives over homepages that happen
    # to list some articles.
    #
    # @return [Result, nil] Result if found, nil otherwise
    def try_link_analysis
      Rails.logger.info("[ArchivePageDetector] Analyzing links from origin...")

      # Fetch the origin page
      origin_result = fetch_and_parse(@origin)
      return nil unless origin_result

      origin_html, _origin_final_url = origin_result

      # Check if homepage looks like an archive (we'll use this as fallback)
      homepage_is_archive = WebProcessor.contains_valid_archive?(origin_html, @origin, min_links: 1)
      if homepage_is_archive
        Rails.logger.info("[ArchivePageDetector] Homepage looks like an archive, checking for dedicated archive pages first...")
      end

      # Find archive-like links in navigation (e.g., /blog, /archive, /posts)
      candidates = find_archive_candidates(origin_html)
      Rails.logger.info("[ArchivePageDetector] Found #{candidates.length} candidate links")

      # Score and validate each candidate, looking for dedicated archive pages
      best_candidate = nil
      best_score = 0

      candidates.each do |candidate|
        candidate_url = resolve_url(candidate[:href])
        next if
          candidate_url.nil? ||
          normalize_path(candidate_url) == normalize_path(@user_url) ||
          normalize_path(candidate_url) == normalize_path(@origin) ||
          # Skip individual article URLs that carry a date (e.g. /2025/11/3/post).
          # article_like_path? is intentionally not used: it accepts any non-excluded
          # path (including /blog, /archive), so it would reject every real candidate.
          WebProcessor::DateExtractor.extract_date_from_path(candidate_url).present?

        result = fetch_and_parse(candidate_url)
        unless result
          log_decision(strategy: "link_analysis", candidate_url: candidate_url, accepted: false, reason: "Fetch failed")
          next
        end

        html, final_url = result

        if WebProcessor.contains_valid_archive?(html, final_url)
          score = calculate_candidate_score(html, final_url, candidate[:text])
          log_decision(strategy: "link_analysis", candidate_url: final_url, accepted: false, reason: "Scored as candidate (link text: '#{candidate[:text]}')", score: score)

          if score > best_score
            best_score = score
            best_candidate = {
              url: final_url,
              html: html,
              score: score,
              text: candidate[:text]
            }
          end
        else
          log_decision(strategy: "link_analysis", candidate_url: final_url, accepted: false, reason: "Not a valid archive")
        end
      end

      # A homepage that is itself a valid archive should not be displaced by a weak
      # candidate (e.g. an article page that merely lists other posts in a sidebar).
      # Such a candidate only wins when it is a genuinely dedicated archive page or
      # scores clearly above the incidental matches a homepage tends to surface.
      candidate_beats_homepage =
        best_candidate && (!homepage_is_archive || strong_candidate?(best_candidate))

      if candidate_beats_homepage
        result_from_candidate(best_candidate)
      elsif homepage_is_archive
        result_from_homepage(origin_html)
      elsif best_candidate
        # Homepage is not an archive either, so a weak candidate still beats nothing.
        result_from_candidate(best_candidate)
      else
        log_decision(strategy: "link_analysis", candidate_url: @origin, accepted: false, reason: "No valid archive candidates found")
        nil
      end
    end

    # Whether a candidate is strong enough to displace a homepage that is itself a
    # valid archive: either a dedicated archive page (archive keyword in its URL
    # path) or a high enough candidate score.
    def strong_candidate?(candidate)
      UrlUtils.path_segments(candidate[:url]).any? { |seg| archive_segment?(seg) } ||
        candidate[:score] >= STRONG_CANDIDATE_SCORE
    end

    # Builds a link-analysis Result for the winning candidate page.
    def result_from_candidate(candidate)
      pagination = detect_pagination(candidate[:html])
      confidence = [ 0.5 + (candidate[:score] * 0.3), 0.85 ].min

      Rails.logger.info("[ArchivePageDetector] Best candidate: #{candidate[:url]} (score: #{candidate[:score]}, pagination: #{pagination})")
      log_decision(strategy: "link_analysis", candidate_url: candidate[:url], accepted: true, reason: "Best candidate via link analysis (link text: '#{candidate[:text]}')", score: confidence.round(2))

      Result.new(
        url: candidate[:url],
        method: "link_analysis",
        confidence_score: confidence.round(2),
        pagination_detected: pagination,
        notes: "Found via link analysis (link text: '#{candidate[:text]}')"
      )
    end

    # Builds a link-analysis Result that falls back to the homepage when it is itself
    # a valid archive and no dedicated archive page beat it.
    def result_from_homepage(origin_html)
      pagination = detect_pagination(origin_html)
      Rails.logger.info("[ArchivePageDetector] Using homepage as archive (pagination: #{pagination})")
      log_decision(strategy: "link_analysis", candidate_url: @origin, accepted: true, reason: "Homepage contains valid archive (fallback)", score: 0.7)

      Result.new(
        url: @origin,
        method: "link_analysis",
        confidence_score: 0.7,
        pagination_detected: pagination,
        notes: "Homepage contains valid archive (fallback)"
      )
    end

    # Strategy D: Feed-assisted discovery
    #
    # @return [Result, nil] Result if found, nil otherwise
    def try_feed_assisted
      Rails.logger.info("[ArchivePageDetector] Trying feed-assisted discovery...")

      # Try to find and parse RSS/Atom feed
      feed_urls = discover_feed_urls
      if feed_urls.empty?
        log_decision(strategy: "feed_assisted", candidate_url: @origin, accepted: false, reason: "No RSS/Atom feed discovered")
        return nil
      end

      post_urls = []
      feed_urls.each do |feed_url|
        urls = parse_feed_for_urls(feed_url)
        post_urls.concat(urls)
        break if post_urls.length >= 5
      end

      if post_urls.length < 3
        log_decision(strategy: "feed_assisted", candidate_url: @origin, accepted: false, reason: "Feed yielded fewer than 3 post URLs")
        return nil
      end

      Rails.logger.info("[ArchivePageDetector] Found #{post_urls.length} URLs from feed")

      # Check if origin links to multiple feed items (making it an archive)
      origin_result = fetch_and_parse(@origin)
      unless origin_result
        log_decision(strategy: "feed_assisted", candidate_url: @origin, accepted: false, reason: "Fetch failed")
        return nil
      end

      origin_html, _origin_final_url = origin_result

      if pages_links_to_feed_items?(origin_html, post_urls, 3)
        pagination = detect_pagination(origin_html)
        log_decision(strategy: "feed_assisted", candidate_url: @origin, accepted: true, reason: "Origin links to multiple feed items", score: 0.75)

        return Result.new(
          url: @origin,
          method: "feed_assisted",
          confidence_score: 0.75,
          pagination_detected: pagination,
          notes: "Origin links to multiple feed items"
        )
      end

      log_decision(strategy: "feed_assisted", candidate_url: @origin, accepted: false, reason: "Origin does not link to enough feed items")
      nil
    end

    # Catches combined slugs like `/all-posts` or `/blog-archive`
    def archive_segment?(segment)
      tokens = segment.split("-")
      tokens.any? && tokens.all? { |t| KNOWN_ARCHIVE_WORDS.include?(t) }
    end

    # Finds archive-like link candidates from HTML
    #
    # @param html [Nokogiri::HTML::Document] The parsed HTML
    # @return [Array<Hash>] Array of { href:, text: } hashes
    def find_archive_candidates(html)
      candidates = []

      # Look for links in nav, header, or with archive-like text
      html.css("nav a, header a, a").each do |link|
        href = link["href"]
        next if href.blank?
        next if href.start_with?("#", "mailto:", "javascript:")

        text = link.text.strip.downcase
        # Match archive-like path segments (e.g. `/blog`, `/posts`, `/articles`, `/all-posts`, `/blog-archive`)
        href_match = UrlUtils.path_segments(href).any? { |seg| archive_segment?(seg) }
        # Match archive-like link text (e.g. `archive`, `all posts`)
        link_text_match = text.match?(ARCHIVE_LINK_TEXT_PATTERN)

        # Prioritize links and titles with archive-like keywords
        if href_match || link_text_match
          candidates << { href: href, text: link.text.strip, priority: 1 }
        elsif href.match?(%r{/blog|/posts|/articles|/writing}i)
          candidates << { href: href, text: link.text.strip, priority: 2 }
        end
      end

      # Sort by priority and dedupe
      candidates.sort_by { |c| c[:priority] }.uniq { |c| c[:href] }.first(10)
    end

    # Calculates a score for an archive candidate
    #
    # @param doc [Nokogiri::HTML::Document] The candidate page HTML
    # @param url [String] The candidate URL
    # @param link_text [String] The text of the link that led here
    # @return [Float] Score from 0.0 to 1.0
    def calculate_candidate_score(doc, url, link_text)
      score = 0.0

      # Link text contains archive keywords (word-boundary, so "Call" != "all")
      if link_text.match?(ARCHIVE_LINK_TEXT_PATTERN)
        score += 0.3
      end

      # URL path has an archive-keyword segment (so /blog counts, /build-a-blog-site doesn't)
      if UrlUtils.path_segments(url).any? { |seg| archive_segment?(seg) }
        score += 0.2
      end

      # Focus on main content area to avoid counting nav/footer elements. Falls back
      # to the whole document when no known container selector matches, since
      # find_container returns nil in that case.
      content_area = WebProcessor::ArchiveContainerExtractor.find_container(url, doc) || doc

      # Has article-like DOM structure
      article_count = content_area.css("article, .post, .entry, .h-entry").length
      if article_count >= 3
        score += 0.2
      end

      # Has time/date elements near links
      time_elements = content_area.css("time, .date, .post-date").length
      if time_elements >= 3
        score += 0.15
      end

      # Has pagination
      if detect_pagination(doc)
        score += 0.15
      end

      [ score, 1.0 ].min
    end

    # Detects pagination controls in HTML
    #
    # @param html [Nokogiri::HTML::Document] The parsed HTML
    # @return [Boolean] True if pagination is detected
    def detect_pagination(html)
      # Check for rel="next" or rel="prev"
      return true if html.at_css('link[rel="next"], link[rel="prev"], a[rel="next"], a[rel="prev"]')

      # Check for pagination container classes and aria-label
      return true if html.at_css(
        ".pagination, .pager, .page-numbers, nav.pages, " \
        "[aria-label*='pagination'], [aria-label*='Pagination'], " \
        ".nav-links, .post-navigation"
      )

      # Check for page number links and pagination text
      html.css("a[href]").each do |link|
        href = link["href"].to_s
        next if href.blank?

        # Check URL patterns
        return true if PAGINATION_PATTERNS.any? { |pattern| href.match?(pattern) }

        # Check link text patterns
        link_text = link.text.strip
        return true if PAGINATION_TEXT_PATTERNS.any? { |pattern| link_text.match?(pattern) }
      end

      false
    end

    # Discovers RSS/Atom feed URLs from the origin
    #
    # @return [Array<String>] Feed URLs
    def discover_feed_urls
      feeds = []

      # Try to find feed links in the origin page
      origin_result = fetch_and_parse(@origin)
      if origin_result
        origin_html, _origin_final_url = origin_result
        origin_html.css('link[type="application/rss+xml"], link[type="application/atom+xml"]').each do |link|
          href = link["href"]
          feeds << resolve_url(href) if href.present?
        end
      end

      # Try common feed paths
      common_feed_paths = %w[/feed /rss /rss.xml /atom.xml /feed.xml /index.xml]
      common_feed_paths.each do |path|
        feed_url = "#{@origin}#{path}"
        head_result = safe_head(feed_url)
        if head_result && (200..299).cover?(head_result[:status])
          feeds << feed_url
        end
      end

      feeds.uniq.first(3)
    end

    # Parses a feed and extracts post URLs
    #
    # @param feed_url [String] The feed URL
    # @return [Array<String>] Post URLs from the feed
    def parse_feed_for_urls(feed_url)
      require "rss"

      content = safe_fetch(feed_url)
      return [] unless content

      urls = []
      begin
        feed = RSS::Parser.parse(content, false)
        return [] unless feed

        items = feed.respond_to?(:items) ? feed.items : (feed.respond_to?(:entries) ? feed.entries : [])
        items.first(10).each do |item|
          url = item.respond_to?(:link) ? item.link : nil
          url ||= item.respond_to?(:url) ? item.url : nil

          # Handle Atom feeds where link might be an object
          if url.respond_to?(:href)
            url = url.href
          end

          urls << url if url.present?
        end
      rescue RSS::Error, StandardError => e
        Rails.logger.warn("[ArchivePageDetector] Failed to parse feed #{feed_url}: #{e.message}")
      end

      urls
    end

    # Checks if a page links to multiple feed item URLs
    #
    # @param html [Nokogiri::HTML::Document] The page HTML
    # @param post_urls [Array<String>] URLs from the feed
    # @param min_matches [Integer] Minimum matches required
    # @return [Boolean]
    def pages_links_to_feed_items?(html, post_urls, min_matches)
      page_links = html.css("a[href]").map { |a| a["href"] }.compact.map { |href| resolve_url(href) }.compact

      matches = post_urls.count { |url| page_links.include?(url) }
      matches >= min_matches
    end

    # Appends a structured decision entry to Thread.current[:playground_detection_log]
    # when set, mirroring playground_fetch_log. A no-op in production where the
    # thread-local is never initialized.
    #
    # @param strategy [String] The strategy that made the decision
    # @param candidate_url [String] The URL the decision is about
    # @param accepted [Boolean] Whether the candidate was accepted as the archive
    # @param reason [String] Short human-readable explanation
    # @param score [Float, nil] Confidence or candidate score, when available
    def log_decision(strategy:, candidate_url:, accepted:, reason:, score: nil)
      if (log = Thread.current[:playground_detection_log])
        log << {
          strategy: strategy,
          candidate_url: candidate_url,
          accepted: accepted,
          reason: reason,
          score: score
        }
      end
    end

    # Fetches and parses HTML from a URL
    #
    # Returns both the parsed HTML and the final URL after any redirects.
    # This allows callers to use the canonical URL for validation and results.
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
    # Returns a hash with :content and :final_url from WebFetcher.
    #
    # @param url [String] The URL to fetch
    # @return [Hash, nil] Hash with :content and :final_url, or nil on error
    def safe_fetch(url)
      @fetcher.fetch(url)
    rescue WebFetcher::FetchError => e
      Rails.logger.debug("[ArchivePageDetector] Fetch failed for #{url}: #{e.message}")
      nil
    end

    # Safely performs HEAD request, returning nil on error
    #
    # Returns a hash with :status, :headers, and :final_url from WebFetcher.
    #
    # @param url [String] The URL to probe
    # @return [Hash, nil] Hash with :status, :headers, :final_url, or nil on error
    def safe_head(url)
      @fetcher.head(url)
    rescue WebFetcher::FetchError => e
      Rails.logger.debug("[ArchivePageDetector] HEAD failed for #{url}: #{e.message}")
      nil
    end

    # Resolves a potentially relative URL to absolute
    #
    # @param href [String] The href to resolve
    # @return [String, nil]
    def resolve_url(href)
      return nil if href.blank?

      uri = Addressable::URI.parse(href)
      if uri.absolute?
        return nil unless href.start_with?(@origin)
        href
      else
        "#{@origin}#{href.start_with?('/') ? '' : '/'}#{href}"
      end
    rescue Addressable::URI::InvalidURIError
      nil
    end

    # Normalizes URL path for comparison
    #
    # @param url [String] The URL
    # @return [String] Normalized path
    def normalize_path(url)
      Addressable::URI.parse(url).path.chomp("/")
    rescue Addressable::URI::InvalidURIError
      url
    end
end
