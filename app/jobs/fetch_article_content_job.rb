class FetchArticleContentJob < ApplicationJob
  include ErrorReportable

  queue_as :content_fetcher

  # Custom error for permanent failures (e.g., 404, 403)
  class PermanentContentError < StandardError; end

  # Retry on transient failures with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    # Called when all retries exhausted
    article = Article.find_by(id: job.arguments.first)
    Rails.logger.warn "[FetchArticleContentJob] RETRIES_EXHAUSTED: article_id=#{job.arguments.first} url=#{article&.url} error=#{error.message}"
    # Mark as failed to fetch content
    article.update!(content_fetch_failed_at: Time.current)

    # Report to content_error_groups for observability
    job.report_retries_exhausted(error, subject: article)
  end

  # Discard job if article no longer exists
  discard_on ActiveRecord::RecordNotFound

  # Discard job on permanent errors (404, 403, etc.) - don't retry
  discard_on PermanentContentError do |job, error|
    article = Article.find_by(id: job.arguments.first)
    Rails.logger.debug "[FetchArticleContentJob] PERMANENT_ERROR_DISCARDED: article_id=#{job.arguments.first} url=#{article&.url} error=#{error.message}"
  end

  # Discard job if fixture not found (mock mode only) - no point retrying
  discard_on WebFetcher::FixtureNotFoundError do |job, error|
    article = Article.find_by(id: job.arguments.first)
    Rails.logger.debug "[FetchArticleContentJob] FIXTURE_NOT_FOUND: article_id=#{job.arguments.first} url=#{article&.url} error=#{error.message}"
  end

  # Fetch full content for a single article
  #
  # @param article [Article] The article to fetch content for
  # @param user_id [Integer, nil] Optional user ID for subscription creation when processing completes
  # @param force [Boolean] If true, only check minimum interval (for manual refresh)
  def perform(article, user_id: nil, force: false)
    Rails.logger.tagged("FetchArticleContentJob") do
      self.error_reporting_subject = article

      Rails.logger.debug { "Fetching content for article: #{article.url} (force: #{force})" }

      # Fetch HTML first to compute hash before extraction
      html_content = WebFetcher.fetch(article.url)[:content]
      new_hash = Digest::SHA256.hexdigest(html_content)
      article.update!(status: "extracting")

      # Skip extraction if content hash hasn't changed (but still update timestamp)
      if article.content_hash == new_hash
        Rails.logger.debug { "Content unchanged (hash match), skipping extraction" }
        article.update!(last_content_fetched_at: Time.current)
        return
      end

      # Extract article content using defuddle (pass pre-fetched HTML)
      result = WebProcessor.extract_article_content(article.url, html: html_content)

      if result && result[:content]
        # Success - update article with content, hash, and fetch timestamp
        store_article(article, result[:content], new_hash)
      elsif result && result[:error] && permanent_error?(result[:error])
        # Permanent error (404, 403, etc.) - don't retry, but mark as fetched
        article.update!(
          last_content_fetched_at: Time.current,
          content_fetch_failed_at: Time.current,
          status: "failed"
        )
        error_msg = "Permanent error extracting content for article #{article.id}: #{result[:error]}"
        Rails.logger.warn { error_msg }
        raise PermanentContentError, error_msg
      else
        # Transient error - retry
        error_msg = "Failed to extract content for article #{article.id}: #{result&.dig(:error) || 'unknown error'}"
        Rails.logger.warn { error_msg }
        raise error_msg
      end

    # Error reporting - ensure all failures are captured in content_error_groups
    rescue WebFetcher::FetchError => e
      article.update!(status: "failed")
      # If 4XX use severity client-error
      if permanent_error_status?(e.http_status)
        report_error(e, phase: "fetch", operation: "article_html_fetch", severity: "client-error")
        raise PermanentContentError, e.message
      else
        report_error(e, phase: "fetch", operation: "article_html_fetch")
        raise
      end
    rescue PermanentContentError => e
      article.update!(status: "failed")
      report_error(e, phase: "process", operation: "article_defuddle_extract", severity: "client-error")
      raise
    rescue StandardError => e
      Rails.logger.error { "Unexpected error in FetchArticleContentJob: #{e.message}" }
      article.update!(status: "failed")
      report_error(e, phase: "process", operation: "article_defuddle_extract")
      raise
    end
  end

  private
    # Stores the article content and creates a version
    def store_article(article, content, new_hash)
      cleaned_title = WebProcessor::TitleCleaner.clean_article_title(content[:title], article)

      ActiveRecord::Base.transaction do
        article.update!(
          title: cleaned_title,
          content_html: content[:content_html],
          content_md: content[:content_md],
          word_count: content[:word_count],
          publication_date: content[:published] || article.publication_date,
          content_hash: new_hash,
          last_content_fetched_at: Time.current,
          status: "completed"
        )

        article.article_versions.create!(
          version: article.next_version_number,
          title: cleaned_title,
          content_html: content[:content_html],
          content_md: content[:content_md],
          content_hash: new_hash,
          word_count: content[:word_count],
          publication_date: content[:published] || article.publication_date
        )
      end
      Rails.logger.debug { "Successfully updated article: #{cleaned_title} (#{content[:word_count] || 0} words)" }
    end
    # Determines if an error is permanent (should not retry)
    # HTTP 4xx errors (except 429 Too Many Requests) are considered permanent
    #
    # @param error_message [String] The error message from extraction
    # @return [Boolean] true if the error is permanent
    def permanent_error?(error_message)
      return false if error_message.blank?
      error_message.match?(/HTTP error! status: (40[0-8]|41[0-8]|451)/)
    end

    def permanent_error_status?(http_status)
      return false if http_status.nil?
      (400..418).include?(http_status) || http_status == 451
    end
end
