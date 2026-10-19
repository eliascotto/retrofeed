class CrawlArchiveJob < ApplicationJob
  queue_as :archive_crawler

  # Crawl an archive page to discover and create articles
  # This is Stage 1 of the crawling pipeline
  #
  # @param url [String] The archive URL to crawl
  # @param force [Boolean] If true, only check minimum interval (for manual refresh)
  # @param detection_method [String, nil] How the archive was detected (user_provided, known_path, etc.)
  # @param confidence_score [Float, nil] Confidence score from detection (0.0-1.0)
  # @param pagination_detected [Boolean, nil] Whether pagination was detected on the archive
  def perform(url, force: false, detection_method: nil, confidence_score: nil, pagination_detected: nil)
    Rails.logger.tagged("CrawlArchiveJob") do
      Rails.logger.debug { "Starting archive crawl for URL: #{url} (force: #{force})" }
      domain = UrlUtils.extract_domain(url)
      website = Website.find_or_initialize_by(domain: domain)
      website.update!(processing_status: "crawling")

      # Fetch the archive page HTML
      Rails.logger.debug { "Fetching HTML from: #{url}" }
      archive_html = fetch_url(url)

      # Validate archive structure
      unless WebProcessor.contains_valid_archive?(archive_html, url)
        Rails.logger.error("Archive validation failed - URL does not contain a valid archive")
        raise WebProcessor::InvalidArchiveError, "The URL does not contain a valid archive"
      end

      # Fetch website index page to extract title
      unless WebFetcher.mock_mode?
        index_url = URI.parse(url).origin
        Rails.logger.debug { "Fetching website index page to extract title: #{index_url}" }
        index_html = fetch_url(index_url)
      else
        index_html = nil
      end

      website_title = WebProcessor.extract_website_title(index_html, archive_html, url)
      if website_title.present?
        Rails.logger.debug { "Extracted website title: '#{website_title}'" }
      else
        Rails.logger.warn { "Could not extract website title (domain: #{domain}, archive_url: #{url}, index_url: #{index_url})" }
      end

      # Extract favicon URL from index page (preferred) or archive page
      favicon_url = extract_favicon_url(index_html, archive_html, url)
      if favicon_url.present?
        Rails.logger.debug { "Extracted favicon URL: '#{favicon_url}'" }
      end

      # Create or update website record (persist even if title is missing)
      if website_title.present?
        website.name = website_title
      end
      website.archive_url = url
      website.last_crawled_at = Time.current

      # Persist detection metadata if provided
      if detection_method.present?
        website.archive_detection_method = detection_method
      end
      if confidence_score.present?
        website.archive_confidence_score = confidence_score
      end
      if !pagination_detected.nil?
        website.archive_paginated = pagination_detected
      end

      website.save!
      Rails.logger.debug { "Website record: #{website.name || website.domain} (id: #{website.id})" }

      # Set processing status to extracting (content fetching phase)
      website.update!(
        processing_status: "extracting",
        processing_started_at: Time.current,
        processing_error_message: nil,
        processing_failed_at: nil
      )

      # Download and attach favicon (don't fail if favicon download fails)
      if favicon_url.present?
        download_favicon(website, favicon_url)
      end

      # Enqueue pagination job if pagination was detected and eligible
      if website.should_paginate?
        Rails.logger.debug { "Pagination detected for #{domain} - enqueueing PaginateArchiveJob" }
        PaginateArchiveJob.perform_later(website.id)
      end

      # Extract articles from archive
      Rails.logger.debug { "Extracting articles from archive..." }
      results = WebProcessor.extract_articles_from_archive(archive_html, url)
      articles_data = results.fetch(:articles, [])
      Rails.logger.debug { "Found #{articles_data.length} articles in archive" }

      # Create article records from the archive. Content is fetched only on
      # demand for a single article, never automatically for the whole site.
      articles_data.each_with_index do |article_data, index|
        Rails.logger.debug { "Processing article #{index + 1}/#{articles_data.length}: #{article_data[:url]}" }

        begin
          article = Article.find_or_initialize_by(url: article_data[:url])
          is_new = article.new_record?

          # Set basic attributes from archive data
          article.website = website
          if article.title.blank? && article_data[:title].present?
            article.title = WebProcessor::TitleCleaner.clean_archive_title(article_data[:title], website)
          end
          if article.title.nil?
            Rails.logger.debug { "Article without Title! #{article_data[:title]}" }
          end
          article.publication_date ||= article_data[:date]
          article.save!

          if is_new
            Rails.logger.debug { "Created new article: #{article.title || article.url}" }
          else
            Rails.logger.debug { "Found existing article: #{article.title || article.url}" }
          end
        rescue ActiveRecord::RecordNotUnique
          # Handle race condition where article was created by another process
          Rails.logger.warn("Duplicate article detected (race condition): #{article_data[:url]}")
          next
        end
      end

      # Articles are now content-fetched only on demand. Finalise here unless
      # pagination is still running (PaginateArchiveJob finalises in that case).
      website.finalize_processing! unless website.should_paginate?

      Rails.logger.debug { "Completed archive crawl for #{domain}, #{articles_data.length} articles found" }
    rescue WebFetcher::FetchError => e
      failed_url = url.presence || e.try(:url) || url
      Rails.logger.error("FETCH FAILED")
      Rails.logger.error("URL: #{failed_url}")
      Rails.logger.error("Error: #{e.class.name} - #{e.message}")
      Rails.logger.error("HTTP Status: #{e.respond_to?(:http_status) ? e.http_status : 'N/A'}")
      ErrorReporter.record(
        phase: "fetch",
        operation: "website_archive_fetch",
        message: e.message,
        exception: e,
        url: failed_url,
        domain: domain,
        job: self,
        http: UrlUtils.http_context_from_exception(e)
      )
      # Mark website as failed if it exists
      mark_website_failed(website, e.message)
      raise WebProcessor::InvalidArchiveError, "Failed to fetch URL: #{e.message}"
    rescue WebProcessor::InvalidArchiveError => e
      Rails.logger.error("ARCHIVE VALIDATION FAILED")
      Rails.logger.error("URL: #{url}")
      Rails.logger.error("Error: #{e.class.name} - #{e.message}")
      ErrorReporter.record(
        phase: "process",
        operation: "website_archive_validate",
        message: e.message,
        exception: e,
        url: url,
        domain: domain,
        job: self
      )
      # Mark website as failed if it exists
      mark_website_failed(website, e.message)
      raise
    rescue StandardError => e
      Rails.logger.error("UNEXPECTED ERROR")
      Rails.logger.error("URL: #{url}")
      Rails.logger.error("Error: #{e.class.name} - #{e.message}")
      Rails.logger.error("Backtrace:\n#{e.backtrace.first(10).join("\n")}") if e.backtrace
      ErrorReporter.record(
        phase: "process",
        operation: "website_archive_crawl",
        message: e.message,
        exception: e,
        url: url,
        domain: domain,
        job: self
      )
      # Mark website as failed if it exists
      mark_website_failed(website, e.message)
      raise
    end
  end

  private
    # Extracts favicon URL from index page (preferred) or archive page
    #
    # @param index_html [Nokogiri::HTML::Document, nil] Parsed index page HTML
    # @param archive_html [Nokogiri::HTML::Document] Parsed archive page HTML
    # @param base_url [String] The base URL for resolving relative URLs
    # @return [String, nil] The favicon URL, or nil if not found
    def extract_favicon_url(index_html, archive_html, base_url)
      # Try index page first (preferred)
      if index_html.present?
        favicon_url = FaviconExtractor.extract_favicon_url(index_html, base_url)
        return favicon_url if favicon_url.present?
      end

      # Fall back to archive page
      FaviconExtractor.extract_favicon_url(archive_html, base_url)
    end

    # Downloads and attaches favicon to website
    # Wrapped in begin/rescue to ensure favicon download failures don't affect the crawling process
    #
    # @param website [Website] The website to attach the favicon to
    # @param favicon_url [String] The URL of the favicon to download
    def download_favicon(website, favicon_url)
      FaviconDownloader.download_and_attach(website, favicon_url)
    rescue StandardError => e
      Rails.logger.warn { "Failed to download favicon for #{website.domain}: #{e.message}" }
    end

    # Marks a website as failed with error details.
    # Safe to call even if website is nil.
    #
    # @param website [Website, nil] The website to mark as failed
    # @param error_message [String] The error message
    def mark_website_failed(website, error_message)
      return unless website&.persisted?

      website.failed!(reason: error_message)
    rescue StandardError => e
      Rails.logger.error { "Failed to mark website as failed: #{e.message}" }
    end

    def fetch_url(url)
      fetch_result = WebFetcher.fetch(url)
      html_content = fetch_result[:content]
      Rails.logger.debug { "Successfully fetched HTML (#{html_content.length} bytes)" }
      Nokogiri::HTML(html_content)
    end
end
