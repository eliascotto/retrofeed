# Crawls paginated archive pages to discover additional articles
#
# This job handles the pagination stage of the crawling pipeline.
# It runs after CrawlArchiveJob when a website has pagination detected.
#
# The job is:
# - Safe: enforces hard caps on pages, posts, and duration
# - Resumable: stores progress and can continue from last page
# - Idempotent: duplicate articles are handled via unique URL constraint
#
# @example
#   PaginateArchiveJob.perform_later(website.id)
#   PaginateArchiveJob.perform_later(website.id, resume_from_page: 5)
#
class PaginateArchiveJob < ApplicationJob
  queue_as :archive_paginator

  # Crawl paginated archive pages for a website
  #
  # @param website_id [Integer] The website ID to paginate
  # @param resume_from_page [Integer, nil] Optional page number to resume from
  def perform(website_id, resume_from_page: nil)
    Rails.logger.tagged("PaginateArchiveJob") do
      website = Website.find(website_id)

      unless website.should_paginate?
        Rails.logger.debug { "Skipping pagination for website #{website.domain} - not eligible" }
        return
      end

      Rails.logger.info { "Starting pagination for #{website.domain} " \
                          "(resume_from_page: #{resume_from_page || 'none'})" }

      guard = PaginationGuard.new
      scraper = PaginatedArchiveScraper.new(
        start_url: website.archive_url,
        origin: URI.parse(website.archive_url).origin
      )

      start_time = Time.current
      page_limit = website.effective_pagination_page_limit
      post_limit = website.effective_pagination_post_limit
      max_duration = Website.pagination_max_duration
      total_articles_created = 0

      # Track the starting page for resumption
      starting_page = resume_from_page || 2  # Start from page 2 since page 1 was handled by CrawlArchiveJob

      scraper.each_page do |page_number, page_url, _html, articles_data|
        # Skip pages until we reach our starting point (for resume)
        if page_number < starting_page
          next
        end

        # Check duration limit
        elapsed = Time.current - start_time
        if elapsed > max_duration
          halt_pagination!(website, "duration_limit", "Exceeded #{max_duration.to_i}s")
          break
        end

        # Check page limit
        if page_number > page_limit
          halt_pagination!(website, "page_limit", "Exceeded #{page_limit} pages")
          break
        end

        # Check post limit
        if guard.total_posts_discovered > post_limit
          halt_pagination!(website, "post_limit", "Exceeded #{post_limit} posts")
          break
        end

        # Generate content fingerprint for guard
        post_urls = articles_data.map { |a| a[:url] }
        fingerprint = PaginationGuard.generate_fingerprint(page_url, post_urls)

        # Check guard conditions (trap detection)
        page_num_from_url = PaginatedArchiveScraper.extract_page_number(page_url)
        unless guard.safe_to_continue?(
          page_url: page_url,
          page_number: page_num_from_url,
          content_fingerprint: fingerprint,
          discovered_posts: post_urls
        )
          halt_pagination!(website, "trap_detected", guard.halt_subreason, severity: "warn")
          break
        end

        # Create articles from this page
        new_articles = create_articles_from_page(website, articles_data)
        total_articles_created += new_articles

        # Update progress
        website.update!(
          pagination_last_page_scraped: page_number,
          pagination_total_pages_found: page_number
        )

        Rails.logger.debug { "Page #{page_number}: #{articles_data.length} articles found, " \
                             "#{new_articles} new, total #{guard.total_posts_discovered} discovered" }
      end

      # Check if scraper stopped due to fetch error
      if scraper.fetch_error
        halt_pagination!(website, "error", scraper.fetch_error.message, exception: scraper.fetch_error)
      elsif scraper.completed? && !guard.halted? && website.pagination_halted_reason.nil?
        # Successfully completed pagination
        complete_pagination!(website)
      end

      # No downstream job advances processing_status (content is fetched only on
      # demand for single articles), so finalise it here.
      website.finalize_processing!

      Rails.logger.debug { "Finished pagination for #{website.domain}: " \
                           "#{guard.total_pages_visited} pages, #{total_articles_created} new articles" }

    rescue ActiveRecord::RecordNotFound
      Rails.logger.error("Website #{website_id} not found")
    rescue StandardError => e
      Rails.logger.error("Unexpected error for website #{website_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

      website&.update(pagination_halted_reason: "error") if website

      ErrorReporter.record(
        subject: website,
        phase: "process",
        operation: "website_pagination",
        message: e.message,
        exception: e,
        domain: website&.domain,
        job: self
      )
      raise
    end
  end

  private
    # Creates article records from extracted data
    #
    # @param website [Website] The website record
    # @param articles_data [Array<Hash>] Extracted article data
    # @return [Integer] Number of new articles created
    def create_articles_from_page(website, articles_data)
      new_count = 0

      articles_data.each do |article_data|
        begin
          article = Article.find_or_initialize_by(url: article_data[:url])
          is_new = article.new_record?

          article.website = website
          if article.title.blank? && article_data[:title].present?
            article.title = WebProcessor::TitleCleaner.clean_archive_title(article_data[:title], website)
          end

          article.publication_date ||= article_data[:date]
          article.save!

          if is_new
            new_count += 1
            Rails.logger.debug { "Created article: #{article.url}" }
          end
        rescue ActiveRecord::RecordNotUnique
          Rails.logger.debug { "Duplicate article (race condition): #{article_data[:url]}" }
          next
        end
      end

      new_count
    end

    # Halts pagination with a reason and optional error recording
    #
    # @param website [Website] The website record
    # @param reason [String] The halt reason
    # @param message [String, nil] Additional context
    # @param severity [String] Error severity for recording
    # @param exception [Exception, nil] Exception if applicable
    def halt_pagination!(website, reason, message = nil, severity: "error", exception: nil)
      Rails.logger.debug { "Halting pagination for #{website.domain}: #{reason} - #{message}" }

      website.update!(
        pagination_halted_reason: reason,
        pagination_completed_at: Time.current
      )

      # Record trap detections and errors
      if reason == "trap_detected" || reason == "error"
        ErrorReporter.record(
          subject: website,
          phase: "process",
          operation: "website_pagination_#{reason}",
          message: "Pagination halted: #{reason} - #{message}",
          exception: exception,
          domain: website.domain,
          job: self,
          severity: severity
        )
      end
    end

    # Marks pagination as successfully completed
    #
    # @param website [Website] The website record
    def complete_pagination!(website)
      Rails.logger.debug { "Pagination completed for #{website.domain}" }

      website.update!(
        pagination_halted_reason: "completed",
        pagination_completed_at: Time.current
      )
    end
end
