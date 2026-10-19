# Development-only controller for testing website archive detection and article extraction
#
# Provides a playground interface to:
# - Test archive detection for any URL
# - View extracted articles without creating database records
# - Test pagination detection and traversal
# - Manage cached HTML fixtures for offline testing
#
class PlaygroundController < ApplicationController
  layout "minimal"

  # Allow access without authentication for development convenience
  skip_before_action :require_login, if: -> { respond_to?(:require_login, true) }

  before_action :ensure_local

  # Default pagination limit for playground (much lower than production)
  PLAYGROUND_PAGINATION_LIMIT = 10

  # Default max scrolls for infinite scroll (lower than production)
  PLAYGROUND_MAX_SCROLLS = 5

  # GET /playground
  # Display form to enter website URL, or show results if website param is present
  def show
    @stats = Playground::FixtureCache.stats

    # If website query param is present, process and show results
    if params[:website].present?
      @url = params[:website].strip
      @max_pages = (params[:max_pages].presence || PLAYGROUND_PAGINATION_LIMIT).to_i
      @test_pagination = params[:test_pagination] == "1"
      @use_infinite_scroll = params[:use_infinite_scroll] == "1"
      @max_scrolls = (params[:max_scrolls].presence || PLAYGROUND_MAX_SCROLLS).to_i
      @debug = params[:debug] == "1"
      @skip_fixture = params[:skip_fixture] == "1"

      Thread.current[:playground_skip_fixture] = @skip_fixture
      process_url
      Thread.current[:playground_skip_fixture] = false
      render :results
    end
  end

  # POST /playground
  # Redirect to GET with query parameters for shareable URLs
  def create
    url = params[:url]&.strip

    if url.blank?
      @error = "URL cannot be blank"
      @stats = Playground::FixtureCache.stats
      render :show
      return
    end

    # Build query parameters
    query_params = { website: url }
    query_params[:max_pages] = params[:max_pages] if params[:max_pages].present?
    query_params[:test_pagination] = params[:test_pagination] == "1" ? "1" : "0"
    query_params[:use_infinite_scroll] = params[:use_infinite_scroll] == "1" ? "1" : "0"
    query_params[:max_scrolls] = params[:max_scrolls] if params[:max_scrolls].present?
    query_params[:debug] = "1" if params[:debug] == "1"
    query_params[:skip_fixture] = "1" if params[:skip_fixture] == "1"

    redirect_to playground_path(query_params)
  end

  def process_article
    @url = params[:website].strip
    @results = {
      url: @url,
      article: nil,
      errors: []
    }

    begin
      # Step 1: Validate URL
      validated_url = UrlUtils.validate_and_normalize_url(@url)
      @results[:validated_url] = validated_url

      # Step 2: Extract articles
      process_with_article_extraction(validated_url)

    rescue UrlUtils::InvalidUrlError => e
      @results[:errors] << { type: "invalid_url", message: e.message }
    rescue => e
      @results[:errors] << { type: "unexpected", message: e.message }
    end

    render :article_results
  end

  private
    def process_url
      @results = {
        url: @url,
        pages: [],
        articles: [],
        errors: []
      }

      begin
        # Step 1: Validate URL
        validated_url = UrlUtils.validate_and_normalize_url(@url)
        @results[:validated_url] = validated_url

        # Step 2: Handle infinite scroll or regular archive detection
        if @use_infinite_scroll
          process_with_infinite_scroll(validated_url)
        else
          process_with_archive_detection(validated_url)
        end

        @results[:articles].sort_by! { |article| article[:published_at] || Time.at(0) }.reverse!
      rescue UrlUtils::InvalidUrlError => e
        @results[:errors] << { type: "invalid_url", message: e.message }
      rescue StandardError => e
        Rails.logger.error("[Playground] Unexpected error: #{e.class.name} - #{e.message}")
        Rails.logger.error(e.backtrace.first(10).join("\n"))
        @results[:errors] << { type: "unexpected", message: e.message }
      end
    end

    # Processes a URL using infinite scroll scraping
    #
    # Uses InfiniteScrollScraper to handle pages with JavaScript-loaded content.
    # Bypasses archive detection and uses the URL directly.
    #
    # @param url [String] The validated URL
    def process_with_infinite_scroll(url)
      Rails.logger.info("[Playground] Using infinite scroll for: #{url}")

      begin
        result = WebFetcher::Playground.fetch_with_scroll(
          url,
          max_scrolls: @max_scrolls,
          scroll_wait: 1.0,
          scroll_distance: 1000
        )

        html = Nokogiri::HTML(result[:content])
        archive_domain = UrlUtils.extract_domain(url)

        # Build page info
        page_info = {
          url: result[:final_url] || url,
          source: result[:source],
          fetched_at: result[:fetched_at],
          size: result[:content].bytesize,
          fetcher_type: result[:fetcher_type],
          scroll_count: result[:scroll_count]
        }
        @results[:pages] << page_info

        processor_results = WebProcessor.extract_articles_from_archive(html, url, debug: @debug)

        @results[:articles] = processor_results[:articles].map { |a| format_article(a, 1, archive_domain) }

        # Add extraction debug to results if present
        extraction_debug = processor_results.fetch(:trace, nil)
        if extraction_debug
          extraction_debug.final_url = result[:final_url] if result[:final_url]
          @results[:extraction_debug] = extraction_debug
        end

        # Build archive info for display
        confidence_score = Playground::ConfidenceScore.new(
          articles: articles,
          archive_domain: archive_domain,
        )
        validation_result = confidence_score.validate()
        @results[:archive] = {
          url: url,
          method: "infinite_scroll",
          confidence_score: validation_result[:match_percentage],
          pagination_detected: false,
          notes: "Used infinite scroll with #{result[:scroll_count]} scrolls (max: #{@max_scrolls})",
          validation: validation_result,
          scroll_count: result[:scroll_count],
          max_scrolls: @max_scrolls
        }

        # Add scroll info to results
        @results[:infinite_scroll] = {
          scroll_count: result[:scroll_count],
          max_scrolls: @max_scrolls,
          reached_limit: result[:scroll_count] >= @max_scrolls
        }

      rescue WebFetcher::FetchError => e
        @results[:errors] << {
          type: "infinite_scroll_error",
          message: "Failed to fetch with infinite scroll: #{e.message}",
          http_status: e.http_status
        }
      rescue InfiniteScrollScraper::ScrapingError => e
        @results[:errors] << {
          type: "infinite_scroll_error",
          message: "Infinite scroll scraping failed: #{e.message}"
        }
      end
    end

    # Processes a URL using standard archive detection
    #
    # Tracks every page fetched by ArchivePageDetector (probes, candidates, final
    # archive) via Thread.current[:playground_fetch_log], then marks each with a
    # role so the UI can show the full detection journey.
    #
    # @param url [String] The validated URL
    def process_with_archive_detection(url)
      Thread.current[:playground_fetch_log] = []
      Thread.current[:playground_detection_log] = []
      detection_result = detect_archive(url)
      detection_pages = Thread.current[:playground_fetch_log].dup
      detection_trace = Thread.current[:playground_detection_log].dup
      Thread.current[:playground_fetch_log] = nil
      Thread.current[:playground_detection_log] = nil

      if detection_result[:error]
        @results[:errors] << detection_result[:error]
        @results[:pages] = mark_detection_pages(detection_pages, nil)
        @results[:detection_trace] = detection_trace
        @results[:validation_verdict] = detection_result[:verdict] if detection_result[:verdict]
        return
      end

      @results[:archive] = detection_result[:archive]
      @results[:pages] = mark_detection_pages(detection_pages, detection_result[:archive][:url])
      @results[:detection_trace] = detection_trace
      @results[:articles] = detection_result[:articles]
      @results[:extraction_debug] = detection_result[:extraction_debug] if detection_result[:extraction_debug]
      @results[:validation_verdict] = detection_result[:verdict] if detection_result[:verdict]

      # Step 3: Test pagination if requested and detected
      if @test_pagination && detection_result[:archive][:pagination_detected]
        paginate_archive(detection_result[:archive][:url])
      end
    end

    def detect_archive(url)
      begin
        # Check if a custom detector exists for this URL
        # Custom detectors take precedence and handle both detection and extraction
        custom_detector = build_custom_detector_with_playground_fetcher(url)

        if custom_detector
          return detect_archive_with_custom_detector(url, custom_detector)
        end

        # No custom detector - use default detection and extraction
        detect_archive_with_default_logic(url)

      rescue WebFetcher::FetchError => e
        {
          error: {
            type: "fetch_error",
            message: e.message,
            http_status: e.http_status
          }
        }
      end
    end

    # Handles archive detection and extraction using a custom detector
    #
    # Custom detectors have full control over their sites, including
    # determining the correct archive URL and extracting articles.
    #
    # @param url [String] The user-provided URL
    # @param custom_detector [ArchivePageDetector::BaseDetector] The custom detector instance
    # @return [Hash] Detection result
    def detect_archive_with_custom_detector(url, custom_detector)
      # Run custom detection to get the proper archive URL
      detector_result = run_archive_detection(url)

      if detector_result[:error]
        # Fallback to fetching the user URL and explain why it did not validate.
        html_result = WebFetcher::Playground.fetch(url)
        page_info = build_page_info(url, html_result)
        verdict = WebProcessor.contains_valid_archive_with_reason?(Nokogiri::HTML(html_result[:content]), url)
        return { error: detector_result[:error], page_info: page_info, verdict: verdict }
      end

      archive_url = detector_result[:url]

      # Fetch the detected archive page
      html_result = WebFetcher::Playground.fetch(archive_url)
      html = Nokogiri::HTML(html_result[:content])

      page_info = build_page_info(archive_url, html_result)

      archive_info = {
        url: archive_url,
        method: detector_result[:method],
        detector: custom_detector_name(url),
        strategy: :custom,
        confidence_score: detector_result[:confidence_score],
        pagination_detected: detector_result[:pagination_detected],
        notes: detector_result[:notes]
      }

      # Use the custom detector for article extraction
      # Create a new detector instance with the archive URL for proper extraction
      extraction_detector = build_custom_detector_with_playground_fetcher(archive_url)
      articles = extraction_detector.extract_articles(html, archive_url)

      # For custom detectors, we only set basic debug info (no link-level detail)
      extraction_debug = nil
      if @debug
        extraction_debug = ExtractionTrace.new(
          strategy: :custom,
          base_url: archive_url,
          base_path: UrlUtils.extract_path(archive_url, archive_url) || "/",
          final_url: page_info[:final_url]
        )
      end

      finalize_detection_result(html, archive_info, page_info, articles, extraction_debug: extraction_debug)
    end

    # Handles archive detection and extraction using default logic
    #
    # Always runs archive detection to find the best archive page, even if
    # the user-provided URL looks like an archive. This ensures we prefer
    # dedicated archive pages (e.g., /blog) over homepages with article links.
    #
    # @param url [String] The user-provided URL
    # @return [Hash] Detection result
    def detect_archive_with_default_logic(url)
      # Always run archive detection to find the best archive page
      detector_result = run_archive_detection(url)

      if detector_result[:error]
        # Archive detection failed - fetch user URL for page info and explain why the
        # user-provided URL did not validate as an archive.
        html_result = WebFetcher::Playground.fetch(url)
        page_info = build_page_info(url, html_result)
        verdict = WebProcessor.contains_valid_archive_with_reason?(Nokogiri::HTML(html_result[:content]), url)
        return { error: detector_result[:error], page_info: page_info, verdict: verdict }
      end

      # Fetch the detected archive page
      html_result = WebFetcher::Playground.fetch(detector_result[:url])
      html = Nokogiri::HTML(html_result[:content])

      page_info = build_page_info(detector_result[:url], html_result)

      archive_info = {
        url: detector_result[:url],
        method: detector_result[:method],
        detector: "Default",
        strategy: :hybrid,
        confidence_score: detector_result[:confidence_score],
        pagination_detected: detector_result[:pagination_detected],
        notes: detector_result[:notes]
      }

      # Extract articles using default extraction
      result = WebProcessor.extract_articles_from_archive(html, archive_info[:url], debug: @debug)
      articles = result.fetch(:articles, [])

      # Surface the extraction trace only when debug mode is enabled
      extraction_debug = @debug ? result.fetch(:trace, nil) : nil
      if extraction_debug
        extraction_debug.final_url = page_info[:final_url] if page_info[:final_url]
      end

      # In debug mode, also surface the validation verdict for the chosen archive page
      # so a passing page's link counts are visible alongside the rejection case.
      verdict = @debug ? WebProcessor.contains_valid_archive_with_reason?(html, archive_info[:url]) : nil

      finalize_detection_result(html, archive_info, page_info, articles, extraction_debug: extraction_debug, verdict: verdict)
    end

    # Finalizes the detection result with validation and confidence adjustment
    #
    # @param html [String] The HTML content of the archive page
    # @param archive_info [Hash] Archive detection info
    # @param page_info [Hash] Page fetch info
    # @param articles [Array<Hash>] Extracted articles
    # @param extraction_debug [Hash, nil] Optional debug info from extraction
    # @param verdict [ArchiveVerdict, nil] Optional validation verdict for the archive page
    # @return [Hash] Final detection result
    def finalize_detection_result(html, archive_info, page_info, articles, extraction_debug: nil, verdict: nil)
      # Post-extraction validation: check how many articles belong to the archive domain
      archive_domain = UrlUtils.extract_domain(archive_info[:url])
      available_link_count = WebProcessor::ArticleExtractor.find_article_links(html, archive_info[:url]).length
      confidence_score = Playground::ConfidenceScore.new(
        base_score: archive_info[:confidence_score],
        method: archive_info[:method],
        articles:,
        archive_domain:,
        available_link_count:,
      )
      adjusted_score, score_breakdown, validation_result = confidence_score.calculate()

      archive_info[:confidence_score] = adjusted_score
      archive_info[:score_breakdown] = score_breakdown
      archive_info[:validation] = validation_result

      result = {
        archive: archive_info,
        page_info: page_info,
        articles: articles.map { |a| format_article(a, 1, archive_domain) }
      }

      # Include extraction debug info if present
      result[:extraction_debug] = extraction_debug if extraction_debug
      result[:verdict] = verdict if verdict

      result
    end

    def run_archive_detection(url)
      # Run the standard detector with the playground fetcher injected so all
      # fetches hit the fixture cache (and feed the playground fetch log)
      detector = ArchivePageDetector.new(url, fetcher: WebFetcher::Playground)
      result = detector.detect

      {
        url: result.url,
        method: result.method,
        confidence_score: result.confidence_score,
        pagination_detected: result.pagination_detected,
        notes: result.notes
      }
    rescue ArchivePageDetector::DetectionError => e
      { error: { type: "detection_error", message: e.message } }
    end

    def paginate_archive(archive_url)
      pages_fetched = 1  # Already fetched page 1
      origin = URI.parse(archive_url).origin
      archive_domain = UrlUtils.extract_domain(archive_url)

      # Start from page 2 (page 1 already processed)
      current_url = archive_url

      while pages_fetched < @max_pages
        html_result = WebFetcher::Playground.fetch(current_url)
        html = Nokogiri::HTML(html_result[:content])

        # Find next page URL
        next_url = find_next_page_url(html, current_url, origin)
        break unless next_url

        pages_fetched += 1

        # Fetch next page
        begin
          next_html_result = WebFetcher::Playground.fetch(next_url)
          next_html = Nokogiri::HTML(next_html_result[:content])

          page_info = build_page_info(next_url, next_html_result, page_number: pages_fetched)
          page_info[:role] = "pagination"
          @results[:pages] << page_info

          # Extract articles from this page
          result = WebProcessor.extract_articles_from_archive(next_html, next_url, debug: @debug)
          @results[:articles].concat(result.fetch(:articles, []).map { |a| format_article(a, pages_fetched, archive_domain) })
          @results[:extraction_debug] = result.fetch(:trace, nil)

          current_url = next_url

          # Find next page for next iteration
          next_url = find_next_page_url(next_html, next_url, origin)
          break unless next_url

        rescue WebFetcher::FetchError => e
          @results[:errors] << {
            type: "pagination_fetch_error",
            message: "Failed to fetch page #{pages_fetched}: #{e.message}",
            url: next_url
          }
          break
        end
      end

      @results[:pagination] = {
        pages_fetched: pages_fetched,
        max_pages: @max_pages,
        reached_limit: pages_fetched >= @max_pages,
        has_more: next_url.present?
      }
    end

    def find_next_page_url(html, current_url, origin)
      PaginatedArchiveScraper.find_next_page_url(html, current_url, origin: origin)
    end

    # Builds a custom detector for the URL that uses the playground fetcher
    #
    # Custom detectors often need to fetch additional pages (e.g., month pages
    # for year-based archives). Injecting the playground fetcher ensures any
    # internal fetches are served from (and saved to) the fixture cache.
    #
    # @param url [String] The URL to find a detector for
    # @return [ArchivePageDetector::BaseDetector, nil] Detector instance or nil
    def build_custom_detector_with_playground_fetcher(url)
      detector_class = SiteProfile.for(url)&.detector
      return nil unless detector_class

      detector_class.new(url, fetcher: WebFetcher::Playground)
    end

    # Returns the human-readable name of the custom detector registered for a URL
    #
    # @param url [String] The URL to look up
    # @return [String, nil] The detector class name (demodulized), or nil if none
    def custom_detector_name(url)
      detector_class = SiteProfile.for(url)&.detector
      return nil unless detector_class
      detector_class.name.demodulize
    end

    # Marks detection-phase pages with roles for display
    #
    # All pages start as "probe" (intermediate fetches during detection). The last
    # fetch whose URL matches the resolved archive URL is promoted to "archive".
    #
    # @param pages [Array<Hash>] Fetch log entries collected during detection
    # @param archive_url [String, nil] The resolved archive URL
    # @return [Array<Hash>] Pages with :role set
    def mark_detection_pages(pages, archive_url)
      pages.each { |p| p[:role] = "probe" }

      if archive_url
        archive_page = pages.reverse.find { |p| p[:url] == archive_url }
        archive_page[:role] = "archive" if archive_page
      end

      pages
    end

    # Builds page info hash from fetch result
    #
    # @param url [String] The page URL
    # @param html_result [Hash] The fetch result from WebFetcher::Playground
    # @param page_number [Integer, nil] Optional page number for pagination
    # @return [Hash] Page info hash for results display
    def build_page_info(url, html_result, page_number: nil)
      info = {
        url: url,
        source: html_result[:source],
        fetched_at: html_result[:fetched_at],
        size: html_result[:content].bytesize,
        fetcher_type: html_result[:fetcher_type]
      }
      info[:page_number] = page_number if page_number
      info[:scroll_count] = html_result[:scroll_count] if html_result[:scroll_count]
      info[:final_url] = html_result[:final_url] if html_result[:final_url]
      info
    end

    def format_article(article, page_number, archive_domain = nil)
      article_domain = article[:url].present? ? UrlUtils.extract_domain(article[:url]) : nil
      is_internal = archive_domain && article_domain && article_domain == archive_domain

      {
        title: article[:title],
        url: article[:url],
        date: article[:date],
        page: page_number,
        domain: article_domain,
        is_internal: is_internal
      }
    end

    def process_with_article_extraction(url)
      start_time = Time.current
      # Use ArticleExtractor to extract articles
      result = WebProcessor.extract_article_content(url)
      elapsed = ((Time.current - start_time) * 1000).round(2)

      if result[:error]
        @results[:errors] << { type: "extraction_failed", message: result[:error] }
      else
        @results[:article] = result[:content].slice(:title, :author, :word_count, :content_md, :published)
                                             .merge(url: url)
        @results[:extraction_method] = "defuddle"
        @results[:extraction_time] = elapsed
      end
    end
end
