require "test_helper"

class WebsiteTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "can attach favicon" do
    website = Website.create!(domain: "test-favicon.com", name: "Test Site")

    # Create a simple PNG favicon (1x1 pixel)
    png_data = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82".dup

    website.favicon.attach(
      io: StringIO.new(png_data.force_encoding("BINARY")),
      filename: "favicon.png",
      content_type: "image/png"
    )

    assert website.favicon.attached?
    assert_equal "favicon.png", website.favicon.filename.to_s
    assert_equal "image/png", website.favicon.content_type
  end

  test "favicon attached? returns false when no favicon" do
    website = Website.create!(domain: "no-favicon.com", name: "No Favicon Site")

    assert_not website.favicon.attached?
  end

  test "normalizes domain by stripping www prefix" do
    website = Website.new(domain: "www.example.com", name: "Example")
    website.save!

    assert_equal "example.com", website.domain
  end

  test "domain normalization is case insensitive" do
    website = Website.new(domain: "WWW.Example.COM", name: "Example")
    website.save!

    assert_equal "Example.COM", website.domain
  end

  # ===== progress_stats method tests =====

  test "progress_stats returns zero stats when no articles" do
    website = Website.create!(domain: "empty.com", name: "Empty Site")
    stats = website.progress_stats

    assert_equal 0, stats[:processed]
    assert_equal 0, stats[:total]
    assert_equal 0, stats[:percentage]
    assert_equal false, stats[:is_processing]
  end

  test "progress_stats calculates correctly when all articles processed" do
    website = Website.create!(domain: "complete.com", name: "Complete Site")
    3.times do |i|
      Article.create!(
        website: website,
        title: "Article #{i}",
        url: "https://example.com/article-#{i}",
        content_html: "<p>Content #{i}</p>"
      )
    end

    stats = website.progress_stats

    assert_equal 3, stats[:processed]
    assert_equal 3, stats[:total]
    assert_equal 100, stats[:percentage]
    assert_equal false, stats[:is_processing]
  end

  test "progress_stats calculates correctly when some articles processed" do
    # Website with extracting status but no active jobs should NOT be considered processing
    # This prevents websites from getting stuck in "extracting" status forever
    website = Website.create!(domain: "partial.com", name: "Partial Site", processing_status: "extracting")
    # Create 3 articles, only 2 with content
    Article.create!(
      website: website,
      title: "Article 1",
      url: "https://example.com/article-1",
      content_html: "<p>Content 1</p>"
    )
    Article.create!(
      website: website,
      title: "Article 2",
      url: "https://example.com/article-2",
      content_md: "# Content 2"
    )
    Article.create!(
      website: website,
      title: "Article 3",
      url: "https://example.com/article-3",
      content_html: nil,
      content_md: nil
    )

    stats = website.progress_stats

    assert_equal 2, stats[:processed]
    assert_equal 3, stats[:total]
    assert_equal 1, stats[:pending]
    assert_equal 67, stats[:percentage] # 2/3 * 100 = 66.67, rounded to 67
    # is_processing should be false when no jobs are running (even with pending articles)
    # This is correct behavior - prevents getting stuck in "extracting" status
    assert_equal false, stats[:is_processing]
  end

  test "progress_stats sets is_processing to false when no articles processed" do
    website = Website.create!(domain: "none.com", name: "None Processed Site")
    2.times do |i|
      Article.create!(
        website: website,
        title: "Article #{i}",
        url: "https://example.com/article-#{i}",
        content_html: nil,
        content_md: nil
      )
    end

    stats = website.progress_stats

    assert_equal 0, stats[:processed]
    assert_equal 2, stats[:total]
    assert_equal 0, stats[:percentage]
    assert_equal false, stats[:is_processing] # processed must be > 0
  end

  test "progress_stats includes all articles in total with separate failed count" do
    # Website with extracting status but no active jobs
    website = Website.create!(domain: "failed.com", name: "Failed Site", processing_status: "extracting")
    # Create articles: 2 successful, 1 failed, 1 without content
    Article.create!(
      website: website,
      title: "Success 1",
      url: "https://example.com/success-1",
      content_html: "<p>Content</p>"
    )
    Article.create!(
      website: website,
      title: "Success 2",
      url: "https://example.com/success-2",
      content_html: "<p>Content</p>"
    )
    Article.create!(
      website: website,
      title: "Failed",
      url: "https://example.com/failed",
      content_fetch_failed_at: Time.current,
      failure_reason: "Test failure",
      status: "failed"
    )
    Article.create!(
      website: website,
      title: "No Content",
      url: "https://example.com/no-content",
      content_html: nil,
      content_md: nil
    )

    stats = website.progress_stats

    # Total should include ALL articles (4)
    assert_equal 4, stats[:total]
    # Processed should be 2 (the two successful ones)
    assert_equal 2, stats[:processed]
    # Failed should be 1
    assert_equal 1, stats[:failed]
    # Pending should be 1 (no content, not failed)
    assert_equal 1, stats[:pending]
    assert_equal 50, stats[:percentage] # 2/4 * 100 = 50
    # is_processing should be false when no jobs are running
    assert_equal false, stats[:is_processing]
    assert_equal true, stats[:has_errors]
  end

  test "progress_stats rounds percentage correctly" do
    website = Website.create!(domain: "rounding.com", name: "Rounding Site")
    # Create 3 articles, only 1 processed (33.33% should round to 33)
    Article.create!(
      website: website,
      title: "Processed",
      url: "https://example.com/processed",
      content_html: "<p>Content</p>"
    )
    2.times do |i|
      Article.create!(
        website: website,
        title: "Unprocessed #{i}",
        url: "https://example.com/unprocessed-#{i}",
        content_html: nil,
        content_md: nil
      )
    end

    stats = website.progress_stats

    assert_equal 33, stats[:percentage] # 1/3 * 100 = 33.33, rounded to 33
  end

  # ===== progress_map class method tests =====

  test "progress_map returns empty hash for empty collection" do
    result = Website.progress_map([])
    assert_equal({}, result)
  end

  test "progress_map returns hash with website IDs as keys" do
    website1 = Website.create!(domain: "site1.com", name: "Site 1")
    website2 = Website.create!(domain: "site2.com", name: "Site 2")

    result = Website.progress_map([ website1, website2 ])

    assert_equal 2, result.size
    assert_includes result.keys, website1.id
    assert_includes result.keys, website2.id
  end

  test "progress_map values match progress_stats for each website" do
    website1 = Website.create!(domain: "site1.com", name: "Site 1", processing_status: "extracting")
    website2 = Website.create!(domain: "site2.com", name: "Site 2")

    # Add articles to website1
    Article.create!(
      website: website1,
      title: "Article 1",
      url: "https://example.com/article-1",
      content_html: "<p>Content</p>"
    )
    Article.create!(
      website: website1,
      title: "Article 2",
      url: "https://example.com/article-2",
      content_html: nil,
      content_md: nil
    )

    # website2 has no articles

    result = Website.progress_map([ website1, website2 ])

    # Check website1 stats
    assert_equal 1, result[website1.id][:processed]
    assert_equal 2, result[website1.id][:total]
    assert_equal 50, result[website1.id][:percentage]
    # is_processing should be false when no jobs are running (even with extracting status)
    assert_equal false, result[website1.id][:is_processing]

    # Check website2 stats
    assert_equal 0, result[website2.id][:processed]
    assert_equal 0, result[website2.id][:total]
    assert_equal 0, result[website2.id][:percentage]
    assert_equal false, result[website2.id][:is_processing]
  end

  test "progress_map works with ActiveRecord relation" do
    website1 = Website.create!(domain: "site1.com", name: "Site 1")
    website2 = Website.create!(domain: "site2.com", name: "Site 2")

    # Use includes to match how it's used in controllers
    websites = Website.where(id: [ website1.id, website2.id ]).includes(:articles)
    result = Website.progress_map(websites)

    assert_equal 2, result.size
    assert_includes result.keys, website1.id
    assert_includes result.keys, website2.id
  end

  # ===== is_processing behavior tests =====

  test "is_processing returns true when status is crawling" do
    # Crawling status always means processing is happening
    website = Website.create!(domain: "crawling.com", name: "Crawling Site", processing_status: "crawling")

    stats = website.progress_stats

    assert_equal true, stats[:is_processing]
  end

  test "is_processing returns false when status is extracting with no pending articles" do
    # All articles processed - should not be marked as processing
    website = Website.create!(domain: "done.com", name: "Done Site", processing_status: "extracting")
    Article.create!(
      website: website,
      title: "Article 1",
      url: "https://example.com/article-1",
      content_html: "<p>Content</p>"
    )

    stats = website.progress_stats

    assert_equal 0, stats[:pending]
    assert_equal false, stats[:is_processing]
  end

  test "is_processing returns false when status is extracting with pending but no jobs" do
    # Pending articles but no jobs running - processing has stalled
    website = Website.create!(domain: "stalled.com", name: "Stalled Site", processing_status: "extracting")
    Article.create!(
      website: website,
      title: "Article 1",
      url: "https://example.com/article-1",
      content_html: nil,
      content_md: nil
    )

    stats = website.progress_stats

    assert_equal 1, stats[:pending]
    assert_equal false, stats[:is_processing]
  end

  test "is_processing returns false for completed status" do
    website = Website.create!(domain: "complete.com", name: "Complete Site", processing_status: "completed")
    Article.create!(
      website: website,
      title: "Article 1",
      url: "https://example.com/article-1",
      content_html: "<p>Content</p>"
    )

    stats = website.progress_stats

    assert_equal false, stats[:is_processing]
  end

  test "finalize_processing! transitions an extracting website to completed" do
    website = Website.create!(domain: "finalize.com", name: "Finalize Site", processing_status: "extracting")

    website.finalize_processing!

    assert_equal "completed", website.reload.processing_status
  end

  test "is_processing returns false for failed status" do
    website = Website.create!(domain: "failed.com", name: "Failed Site", processing_status: "failed")

    stats = website.progress_stats

    assert_equal false, stats[:is_processing]
    assert_equal true, stats[:has_errors]
  end

  test "is_processing returns false for partial status" do
    website = Website.create!(domain: "partial.com", name: "Partial Site", processing_status: "partial")
    Article.create!(
      website: website,
      title: "Success",
      url: "https://example.com/success",
      content_html: "<p>Content</p>"
    )
    Article.create!(
      website: website,
      title: "Failed",
      url: "https://example.com/failed",
      content_fetch_failed_at: Time.current,
      failure_reason: "Test failure"
    )

    stats = website.progress_stats

    assert_equal false, stats[:is_processing]
    assert_equal false, stats[:has_errors]
  end

  # ===== formatted_error_message tests =====

  test "formatted_error_message returns nil when error_group is nil" do
    result = Website.formatted_error_message(nil)

    assert_nil result
  end

  test "formatted_error_message formats website_archive_crawl operation" do
    error_group = ContentErrorGroup.create!(
      fingerprint: "test-fingerprint-1",
      phase: "process",
      operation: "website_archive_crawl",
      message: "No unique index found for id",
      severity: "error",
      status: "open",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    result = Website.formatted_error_message(error_group)

    assert_equal "Error during website archive crawling: No unique index found for id", result
  end

  test "formatted_error_message formats website_archive_fetch operation" do
    error_group = ContentErrorGroup.create!(
      fingerprint: "test-fingerprint-2",
      phase: "fetch",
      operation: "website_archive_fetch",
      message: "Connection timeout",
      severity: "error",
      status: "open",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    result = Website.formatted_error_message(error_group)

    assert_equal "Error during website archive fetching: Connection timeout", result
  end

  test "formatted_error_message formats website_archive_validate operation" do
    error_group = ContentErrorGroup.create!(
      fingerprint: "test-fingerprint-3",
      phase: "process",
      operation: "website_archive_validate",
      message: "Invalid archive structure",
      severity: "error",
      status: "open",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    result = Website.formatted_error_message(error_group)

    assert_equal "Error during website archive validation: Invalid archive structure", result
  end

  test "formatted_error_message formats website_pipeline operation" do
    error_group = ContentErrorGroup.create!(
      fingerprint: "test-fingerprint-4",
      phase: "process",
      operation: "website_pipeline",
      message: "Unexpected error during processing",
      severity: "error",
      status: "open",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    result = Website.formatted_error_message(error_group)

    assert_equal "Error during website processing: Unexpected error during processing", result
  end

  test "formatted_error_message uses operation name with underscores replaced for unknown operations" do
    error_group = ContentErrorGroup.create!(
      fingerprint: "test-fingerprint-5",
      phase: "process",
      operation: "unknown_custom_operation",
      message: "Some error message",
      severity: "error",
      status: "open",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    result = Website.formatted_error_message(error_group)

    assert_equal "Error during unknown custom operation: Some error message", result
  end

  test "formatted_error_message truncates long messages to 200 characters" do
    long_message = "A" * 300
    error_group = ContentErrorGroup.create!(
      fingerprint: "test-fingerprint-6",
      phase: "process",
      operation: "website_archive_crawl",
      message: long_message,
      severity: "error",
      status: "open",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    result = Website.formatted_error_message(error_group)

    # The message part should be truncated to 200 chars (with ellipsis)
    assert result.length < 300
    assert result.include?("...")
  end

  # ===== website_level_error tests =====

  test "website_level_error returns error where website is the subject" do
    website = Website.create!(domain: "error-test.com", name: "Error Test", processing_status: "failed")
    error_group = ContentErrorGroup.create!(
      fingerprint: "website-error-1",
      phase: "process",
      operation: "website_archive_crawl",
      message: "Crawl failed",
      severity: "error",
      status: "open",
      subject: website,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    result = website.website_level_error

    assert_equal error_group, result
  end

  test "website_level_error returns nil when no website-level errors exist" do
    website = Website.create!(domain: "no-error.com", name: "No Error", processing_status: "completed")

    result = website.website_level_error

    assert_nil result
  end

  test "website_level_error returns most recent error" do
    website = Website.create!(domain: "multi-error.com", name: "Multi Error", processing_status: "failed")
    new_error = ContentErrorGroup.create!(
      fingerprint: "new-error",
      phase: "process",
      operation: "website_archive_crawl",
      message: "New error",
      severity: "error",
      status: "open",
      subject: website,
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.hour.ago
    )

    result = website.website_level_error

    assert_equal new_error, result
  end

  test "website_level_error ignores resolved errors" do
    website = Website.create!(domain: "resolved.com", name: "Resolved", processing_status: "failed")

    result = website.website_level_error

    assert_nil result
  end

  # ===== progress_stats with website error tests =====

  test "progress_stats includes website_error when processing_status is failed" do
    website = Website.create!(domain: "failed-with-error.com", name: "Failed With Error", processing_status: "failed")
    ContentErrorGroup.create!(
      fingerprint: "website-error-progress",
      phase: "process",
      operation: "website_archive_crawl",
      message: "No unique index found for id",
      severity: "error",
      status: "open",
      subject: website,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    stats = website.progress_stats

    assert_equal true, stats[:has_errors]
    assert_not_nil stats[:website_error]
    assert_equal "website_archive_crawl", stats[:website_error][:operation]
    assert_equal "No unique index found for id", stats[:website_error][:message]
    assert_equal "Error during website archive crawling: No unique index found for id", stats[:website_error][:formatted_message]
  end

  test "progress_stats does not include website_error when processing_status is not failed" do
    website = Website.create!(domain: "completed.com", name: "Completed", processing_status: "completed")

    stats = website.progress_stats

    assert_nil stats[:website_error]
  end

  # ===== formatted_error instance method tests =====

  test "formatted_error returns formatted website level error when present" do
    website = Website.create!(domain: "instance-error.com", name: "Instance Error", processing_status: "failed")
    ContentErrorGroup.create!(
      fingerprint: "instance-website-error",
      phase: "process",
      operation: "website_archive_fetch",
      message: "Connection refused",
      severity: "error",
      status: "open",
      subject: website,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    result = website.formatted_error

    assert_equal "Error during website archive fetching: Connection refused", result
  end

  test "formatted_error returns nil when no errors exist" do
    website = Website.create!(domain: "no-errors.com", name: "No Errors", processing_status: "completed")

    result = website.formatted_error

    assert_nil result
  end

  # ===== refresh_later =====

  test "refresh_later enqueues CrawlArchiveJob with force flag" do
    website = Website.create!(
      domain: "refresh-test.com",
      name: "Refresh Test",
      archive_url: "https://refresh-test.com/archive"
    )

    assert_enqueued_with(job: CrawlArchiveJob) do
      website.refresh_later
    end
  end
end
