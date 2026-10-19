class ProcessWebsiteJob < ApplicationJob
  queue_as :default

  # Process a website URL and create a subscription for the user
  # This job serves as the entry point and orchestrator for the crawling pipeline
  #
  # Pipeline:
  #   1. ProcessWebsiteJob (this job) - validates URL, detects archive (for new sites), delegates to CrawlArchiveJob
  #   2. CrawlArchiveJob - crawls archive, creates articles
  #
  # For new websites (domain not seen before), archive detection runs to find the best
  # archive page. For existing websites, the stored archive_url is used directly.
  #
  # @param url [String] The URL to process
  def perform(url)
    Rails.logger.tagged("ProcessWebsiteJob") do
      Rails.logger.debug { "Starting processing for URL: #{url}" }

      # Validate and normalize URL
      validated_url = UrlUtils.validate_and_normalize_url(url)
      domain = UrlUtils.extract_domain(validated_url)
      Rails.logger.debug { "URL validated: #{validated_url} (domain: #{domain})" }

      existing_website = Website.find_by(domain: domain)

      if WebProcessor.should_crawl_archive?(existing_website, force: false)
        # New website: run archive detection
        Rails.logger.debug { "New website, running archive detection..." }
        detection_result = ArchivePageDetector.detect(url)

        Rails.logger.debug { "Archive detected: #{detection_result.url} " \
                          "(method: #{detection_result.method}, " \
                          "confidence: #{detection_result.confidence_score}, " \
                          "pagination: #{detection_result.pagination_detected})" }

        CrawlArchiveJob.perform_later(
          detection_result.url,
          detection_method: detection_result.method,
          confidence_score: detection_result.confidence_score,
          pagination_detected: detection_result.pagination_detected
        )
      else
        # Existing website: use stored archive_url, skip detection
        Rails.logger.debug { "Existing website found (id: #{existing_website.id}), no need to crawl archive" }
      end

      Rails.logger.debug { "Successfully enqueued crawling pipeline" }

    rescue UrlUtils::InvalidUrlError => e
      Rails.logger.error { "URL VALIDATION FAILED" }
      Rails.logger.error { "URL: #{url}" }
      Rails.logger.error { "Error: #{e.class.name} - #{e.message}" }
      ErrorReporter.record(
        phase: "process",
        operation: "website_url_validate",
        message: e.message,
        exception: e,
        url: url,
        domain: nil,
        job: self
      )
      existing_website&.failed!(reason: "Error: #{e.class.name} - #{e.message}")
      raise
    rescue ArchivePageDetector::DetectionError => e
      Rails.logger.error { "ARCHIVE DETECTION FAILED" }
      Rails.logger.error { "URL: #{url}" }
      Rails.logger.error { "Error: #{e.class.name} - #{e.message}" }
      Rails.logger.error { "Backtrace: #{e.backtrace.first(5).join("\n")}" }
      ErrorReporter.record(
        phase: "process",
        operation: "website_archive_detect",
        message: e.message,
        exception: e,
        url: url,
        domain: UrlUtils.extract_domain(url),
        job: self
      )
      existing_website&.failed!(reason: "Error: #{e.class.name} - #{e.message}")
      raise WebProcessor::InvalidArchiveError, e.message
    rescue StandardError => e
      Rails.logger.error { "UNEXPECTED ERROR" }
      Rails.logger.error { "URL: #{url}" }
      Rails.logger.error { "Error: #{e.class.name} - #{e.message}" }
      Rails.logger.error { "Backtrace:\n#{e.backtrace.first(10).join("\n")}" }
      ErrorReporter.record(
        phase: "process",
        operation: "website_pipeline",
        message: e.message,
        exception: e,
        url: url,
        domain: UrlUtils.extract_domain(url),
        job: self
      )
      existing_website&.failed!(reason: "Error: #{e.class.name} - #{e.message}")
      raise
    end
  end
end
