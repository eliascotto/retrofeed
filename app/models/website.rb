class Website < ApplicationRecord
  has_many :subscriptions, dependent: :destroy
  has_many :users, through: :subscriptions
  has_many :articles, dependent: :destroy
  has_one_attached :favicon

  # Normalize domain by stripping www. prefix before saving
  before_save :normalize_domain

  after_update_commit :broadcast_to_subscribers, if: :saved_change_to_processing_status?

  # Validation for title_suffix_pattern
  validates :title_suffix_pattern, length: { maximum: 255 }, allow_nil: true

  # === Processing Statuses ===
  enum :processing_status, {
    pending:    "pending",
    crawling:   "crawling",
    extracting: "extracting",
    completed:  "completed",
    partial:    "partial",
    failed:     "failed"
  }, default: "pending"

  VALID_TRANSITIONS = {
    "pending"    => %w[crawling extracting failed],
    "crawling"   => %w[extracting failed],
    "extracting" => %w[completed partial failed],
    "completed"  => %w[pending crawling],
    "partial"    => %w[pending crawling],
    "failed"     => %w[pending crawling]
  }.freeze

  validate :validate_processing_status_transition,
    if: :processing_status_changed?,
    unless: :new_record?

  def origin
    if archive_url.present?
      UrlUtils.extract_origin(archive_url)
    else
      nil
    end
  end

  # === Pagination Hard Caps ===
  # These cannot be exceeded under any circumstances
  PAGINATION_MAX_PAGES = 500
  PAGINATION_MAX_POSTS = 10_000
  PAGINATION_MAX_DURATION = 30.minutes
  PAGINATION_MAX_CONSECUTIVE_EMPTY = 3
  PAGINATION_MAX_DUPLICATE_STREAK = 10
  PAGINATION_MAX_PAGE_JUMP = 100

  # Valid halt reasons for pagination
  PAGINATION_HALT_REASONS = %w[
    completed
    page_limit
    post_limit
    duration_limit
    trap_detected
    error
    robots_blocked
  ].freeze

  # Returns the effective page limit for this website
  # Uses per-site override if set, otherwise ENV default, capped by hard max
  #
  # @return [Integer] Maximum pages to crawl
  def effective_pagination_page_limit
    limit = pagination_page_limit || self.class.default_pagination_page_limit
    [ limit, PAGINATION_MAX_PAGES ].min
  end

  # Returns the effective post limit for this website
  # Uses per-site override if set, otherwise ENV default, capped by hard max
  #
  # @return [Integer] Maximum posts to discover
  def effective_pagination_post_limit
    limit = pagination_post_limit || self.class.default_pagination_post_limit
    [ limit, PAGINATION_MAX_POSTS ].min
  end

  # Checks if pagination should be attempted for this website
  # Returns true if pagination is enabled and not recently completed
  #
  # @param force [Boolean] If true, ignore completion time check
  # @return [Boolean]
  def should_paginate?(force: false)
    return false unless archive_paginated?
    return false unless archive_url.present?
    return true if force
    true if pagination_completed_at.nil?
  end

  # Returns the default page limit from ENV or hard-coded default
  #
  # @return [Integer]
  def self.default_pagination_page_limit
    env_limit = ENV.fetch("RETROFEED_PAGINATION_DEFAULT_PAGE_LIMIT", PAGINATION_MAX_PAGES).to_i
    [ env_limit, PAGINATION_MAX_PAGES ].min
  end

  # Returns the default post limit from ENV or hard-coded default
  #
  # @return [Integer]
  def self.default_pagination_post_limit
    env_limit = ENV.fetch("RETROFEED_PAGINATION_DEFAULT_POST_LIMIT", PAGINATION_MAX_POSTS).to_i
    [ env_limit, PAGINATION_MAX_POSTS ].min
  end

  # Returns the max duration for pagination from ENV or hard-coded default
  #
  # @return [ActiveSupport::Duration]
  def self.pagination_max_duration
    env_seconds = ENV.fetch("RETROFEED_PAGINATION_MAX_DURATION_SECONDS", PAGINATION_MAX_DURATION.to_i).to_i
    [ env_seconds, PAGINATION_MAX_DURATION.to_i ].min.seconds
  end

  # Enqueues a forced archive re-crawl, bypassing the normal 14-day interval.
  # Uses the hard minimum interval (60 min) as the only rate-limiting guard.
  def refresh_later
    CrawlArchiveJob.perform_later(archive_url, force: true)
  end

  def processing?
    %w[pending crawling extracting].include?(processing_status)
  end

  # Returns progress stats for the website with comprehensive status detection.
  # Unlike the old implementation, this properly handles failure states and
  # checks actual job queue status to avoid showing "still processing" forever.
  #
  # @return [Hash] Progress stats:
  #   processed: Number of articles with content
  #   total: Total number of articles (including failed)
  #   failed: Number of articles that failed to process
  #   pending: Number of articles waiting to be processed
  #   percentage: Percentage of articles with content
  #   is_processing: true if processing is actually happening
  #   has_errors: true if any articles failed
  #   error_message: Summary of errors if any
  #   processing_status: Current processing status string
  def progress_stats
    # Count all articles (including failed ones for accurate totals)
    total = articles.count
    processed = articles.with_content.count
    failed = articles.where(status: "failed").count
    pending = total - processed - failed

    percentage = total > 0 ? (processed.to_f / total * 100).round : 0

    # A website is only "processing" while actively crawling its archive.
    # Content is fetched on demand per article, so there are no background jobs
    # to wait on, and the brief "extracting" phase is not treated as processing
    # to avoid a website appearing stuck if a crawl is interrupted.
    is_processing = processing_status == "crawling"

    # Determine error state - includes both article failures and website-level failures
    has_website_error = processing_status == "failed"
    has_errors = failed > 0 || has_website_error
    error_message = has_errors ? build_error_summary : nil

    # Build the result hash
    result = {
      processed: processed,
      total: total,
      failed: failed,
      pending: pending,
      percentage: percentage,
      is_processing: is_processing,
      has_errors: has_errors,
      error_message: error_message,
      processing_status: processing_status
    }

    # Add website-level error information when website has failed
    if has_website_error
      website_error = website_level_error
      if website_error
        result[:website_error] = {
          operation: website_error.operation,
          message: website_error.message,
          formatted_message: self.class.formatted_error_message(website_error),
          last_seen_at: website_error.last_seen_at&.iso8601
        }
      end
    end

    result
  end

  # Builds a summary of recent errors for this website.
  # Includes both website-level errors and article-level errors.
  #
  # @return [String, nil] Error summary or nil if no errors
  def build_error_summary
    # Get website-level errors (subject_type='Website')
    website_errors = ContentErrorGroup
      .where(subject_type: "Website", subject_id: id, status: "open")
      .order(last_seen_at: :desc)
      .limit(5)

    # Get article-level errors for this website's articles
    article_errors = ContentErrorGroup
      .joins("INNER JOIN articles ON content_error_groups.subject_id = articles.id AND content_error_groups.subject_type = 'Article'")
      .where(articles: { website_id: id })
      .where(status: "open")
      .order(last_seen_at: :desc)
      .limit(5)

    recent_errors = (website_errors + article_errors).uniq(&:id)
    return nil if recent_errors.empty?

    # Summarize error types
    error_counts = recent_errors.group_by(&:operation).transform_values(&:count)
    error_counts.map { |op, count| "#{op}: #{count}" }.join(", ")
  end

  # Returns the most recent error for this website.
  # Checks both website-level errors and article-level errors.
  #
  # @return [ContentErrorGroup, nil] Most recent error or nil
  def most_recent_error
    # Check website-level error first (most relevant for website failures)
    website_error = website_level_error
    return website_error if website_error

    # Fall back to article-level errors
    ContentErrorGroup
      .joins("INNER JOIN articles ON content_error_groups.subject_id = articles.id AND content_error_groups.subject_type = 'Article'")
      .where(articles: { website_id: id })
      .where(status: "open")
      .order(last_seen_at: :desc)
      .first
  end

  # Returns the most recent website-level error (where this website is the subject).
  # Used specifically for errors that occur during website crawling/processing.
  #
  # @return [ContentErrorGroup, nil] Most recent website-level error or nil
  def website_level_error
    ContentErrorGroup
      .where(subject_type: "Website", subject_id: id, status: "open")
      .order(last_seen_at: :desc)
      .first
  end

  # Maps operation names to user-friendly labels for error messages.
  OPERATION_LABELS = {
    "website_archive_crawl" => "website archive crawling",
    "website_archive_fetch" => "website archive fetching",
    "website_archive_validate" => "website archive validation",
    "website_archive_detect" => "website archive detection",
    "website_pipeline" => "website processing",
    "website_url_validate" => "URL validation",
    "article_html_fetch" => "article fetching",
    "article_defuddle_extract" => "article content extraction"
  }.freeze

  # Formats an error message from a ContentErrorGroup for user display.
  # Uses operation-to-label mapping for user-friendly messages.
  #
  # @param error_group [ContentErrorGroup] The error to format
  # @return [String] Formatted error message like "Error during website archive crawling: message"
  def self.formatted_error_message(error_group)
    return nil unless error_group

    operation = error_group.operation
    label = OPERATION_LABELS[operation] || operation.to_s.tr("_", " ")
    message = error_group.message.to_s.truncate(200)

    "Error during #{label}: #{message}"
  end

  # Instance method wrapper for formatted_error_message
  # Formats the website's most recent error for user display.
  #
  # @return [String, nil] Formatted error message or nil if no error
  def formatted_error
    error = website_level_error || most_recent_error
    self.class.formatted_error_message(error)
  end

  # Returns a map of website IDs to progress stats
  #
  # @param websites [Array<Website>] Websites to get progress stats for
  # @return [Hash] Map of website IDs to progress stats
  def self.progress_map(websites)
    websites.each_with_object({}) do |website, hash|
      hash[website.id] = website.progress_stats
    end
  end

  # Single terminal success transition for the crawl pipeline. Both
  # CrawlArchiveJob and PaginateArchiveJob call this so the "completed" write
  # lives in one place; see Website#failed! for the terminal failure transition.
  def finalize_processing!
    update!(processing_status: "completed")
  end

  def failed!(reason: "")
    update!(
      processing_status: "failed",
      processing_error_message: reason.to_s.truncate(1500),
      processing_failed_at: Time.current
    )
  end

  private
    def broadcast_to_subscribers
      progress = progress_stats
      total_count = articles.count

      subscriptions.includes(:user).find_each do |subscription|
        Turbo::StreamsChannel.broadcast_replace_later_to(
          "user_#{subscription.user_id}",
          target: ActionView::RecordIdentifier.dom_id(self),
          partial: "sites/site_list_item",
          locals: {
            website: self,
            user: subscription.user,
            progress:,
            total_count:,
            new_count: subscription.new_articles_count
          }
        )

        if processing_status == "failed"
          Turbo::StreamsChannel.broadcast_append_later_to(
            "user_#{subscription.user_id}",
            target: "flashes",
            partial: "layouts/shared/flash",
            locals: { message: "Failed to add #{domain}: #{processing_error_message}", level: :error }
          )
        end
      end
    end

    def validate_processing_status_transition
      from = processing_status_was
      to   = processing_status
      unless VALID_TRANSITIONS.fetch(from, []).include?(to)
        errors.add(:processing_status, "cannot transition from '#{from}' to '#{to}'")
      end
    end

    def normalize_domain
      return unless domain.present?

      # Strip www. prefix (case-insensitive)
      self.domain = domain.sub(/\Awww\./i, "")
    end
end
