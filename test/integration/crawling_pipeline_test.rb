require "test_helper"

class CrawlingPipelineTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:test_user)
    @archive_url = "https://overreacted.io/"
    @html_fixture_path = Rails.root.join("test", "fixtures", "websites", "overreacted", "archive.html")
  end

  test "full pipeline: ProcessWebsiteJob triggers complete crawling flow" do
    stub_archive_request(@archive_url, @html_fixture_path)
    stub_content_extraction

    # Mock the archive detector to return the user URL
    detection_result = ArchivePageDetector::Result.new(
      url: @archive_url,
      method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false,
      notes: "User-provided URL validated"
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| detection_result }

    begin
      # Start the pipeline via subscribe_to_url (creates subscription + enqueues ProcessWebsiteJob)
      perform_enqueued_jobs(only: [ ProcessWebsiteJob, CrawlArchiveJob ]) do
        @user.subscribe_to_url(@archive_url)
      end

      # Verify website was created
      website = Website.find_by(domain: "overreacted.io")
      assert_not_nil website, "Website should be created"
      assert_equal @archive_url, website.archive_url
      assert_not_nil website.last_crawled_at

      # Verify detection metadata was persisted
      assert_equal "user_provided", website.archive_detection_method
      assert_equal 1.0, website.archive_confidence_score
      assert_equal false, website.archive_paginated

      # Verify subscription was created
      assert @user.websites.include?(website), "User should be subscribed to the website"

      # Verify articles were created
      assert website.articles.count > 0, "Articles should be created"
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "pipeline crawl creates articles without fetching content automatically" do
    stub_archive_request(@archive_url, @html_fixture_path)

    detection_result = ArchivePageDetector::Result.new(
      url: @archive_url,
      method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false,
      notes: nil
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| detection_result }

    begin
      # Execute only CrawlArchiveJob; content is never fetched automatically
      perform_enqueued_jobs(only: CrawlArchiveJob) do
        ProcessWebsiteJob.perform_now(@archive_url)
      end

      website = Website.find_by(domain: "overreacted.io")

      # Articles are created from the archive but have no content yet
      assert website.articles.count > 0, "Articles should be created"
      assert_equal website.articles.count, website.articles.where(content_html: nil).count,
        "No article should have content fetched automatically"

      # With no pagination, the website is finalised as completed
      assert_equal "completed", website.processing_status
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "pipeline is idempotent for recently crawled websites" do
    stub_archive_request(@archive_url, @html_fixture_path)

    detection_result = ArchivePageDetector::Result.new(
      url: @archive_url,
      method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false,
      notes: nil
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| detection_result }

    begin
      # First crawl
      perform_enqueued_jobs(only: [ ProcessWebsiteJob, CrawlArchiveJob ]) do
        ProcessWebsiteJob.perform_now(@archive_url)
      end

      website = Website.find_by(domain: "overreacted.io")
      original_crawled_at = website.last_crawled_at
      original_article_count = website.articles.count

      # Clear any pending jobs
      clear_enqueued_jobs

      # Second crawl should be skipped (within update interval)
      # Note: For existing websites, detection is NOT run, stored archive_url is used
      ProcessWebsiteJob.perform_now(@archive_url)

      # Should still enqueue CrawlArchiveJob but it should skip processing
      perform_enqueued_jobs(only: [ ProcessWebsiteJob, CrawlArchiveJob ])

      website.reload
      # last_crawled_at should not change significantly (within a second)
      assert_in_delta original_crawled_at.to_f, website.last_crawled_at.to_f, 1.0
      assert_equal original_article_count, website.articles.count
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "pipeline creates subscription without duplicates" do
    stub_archive_request(@archive_url, @html_fixture_path)

    detection_result = ArchivePageDetector::Result.new(
      url: @archive_url,
      method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false,
      notes: nil
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| detection_result }

    begin
      # Run pipeline twice. Second call raises AlreadySubscribedError (handled below).
      2.times do
        perform_enqueued_jobs(only: [ ProcessWebsiteJob, CrawlArchiveJob ]) do
          begin
            @user.subscribe_to_url(@archive_url)
          rescue User::AlreadySubscribedError
            # Expected on second call: subscription already exists
          end
        end
      end

      website = Website.find_by(domain: "overreacted.io")

      # Should only have one subscription
      subscriptions = Subscription.where(user: @user, website: website)
      assert_equal 1, subscriptions.count
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "pipeline handles multiple users subscribing to same website" do
    stub_archive_request(@archive_url, @html_fixture_path)

    other_user = users(:other_user)

    detection_result = ArchivePageDetector::Result.new(
      url: @archive_url,
      method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false,
      notes: nil
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| detection_result }

    begin
      # First user subscribes
      perform_enqueued_jobs(only: [ ProcessWebsiteJob, CrawlArchiveJob ]) do
        @user.subscribe_to_url(@archive_url)
      end

      website = Website.find_by(domain: "overreacted.io")
      original_article_count = website.articles.count

      # Update last_crawled_at to allow re-processing for second user
      website.update!(last_crawled_at: 10.days.ago)

      # Second user subscribes (website exists, so detection is NOT called)
      perform_enqueued_jobs(only: [ ProcessWebsiteJob, CrawlArchiveJob ]) do
        other_user.subscribe_to_url(@archive_url)
      end

      # Both users should be subscribed
      assert @user.websites.include?(website)
      assert other_user.websites.include?(website)

      # Should still only have one website record
      assert_equal 1, Website.where(domain: "overreacted.io").count

      # Article count should remain the same (no duplicates)
      assert_equal original_article_count, website.reload.articles.count
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "pipeline persists detection metadata including pagination flag" do
    stub_archive_request(@archive_url, @html_fixture_path)

    detection_result = ArchivePageDetector::Result.new(
      url: @archive_url,
      method: "known_path",
      confidence_score: 0.9,
      pagination_detected: true,
      notes: "Found at /blog"
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| detection_result }

    begin
      perform_enqueued_jobs(only: [ ProcessWebsiteJob, CrawlArchiveJob ]) do
        ProcessWebsiteJob.perform_now(@archive_url)
      end

      website = Website.find_by(domain: "overreacted.io")

      assert_equal "known_path", website.archive_detection_method
      assert_equal 0.9, website.archive_confidence_score
      assert_equal true, website.archive_paginated

      # Articles should still be created from page 1 even with pagination
      assert website.articles.count > 0, "Articles should be created from page 1"
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "progress_stats correctly reports processing status" do
    stub_archive_request(@archive_url, @html_fixture_path)

    detection_result = ArchivePageDetector::Result.new(
      url: @archive_url,
      method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false,
      notes: nil
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| detection_result }

    begin
      # Setup website with articles
      perform_enqueued_jobs(only: [ ProcessWebsiteJob, CrawlArchiveJob ]) do
        ProcessWebsiteJob.perform_now(@archive_url)
      end

      website = Website.find_by(domain: "overreacted.io")

      # With no pagination, the crawl finalises the website as completed.
      # No content is fetched automatically, so nothing is processed yet.
      stats = website.progress_stats
      assert_equal "completed", stats[:processing_status]
      assert_not stats[:is_processing], "Completed website should not be processing"
      assert_equal 0, stats[:processed], "No articles should be processed yet"
      assert stats[:total] > 0, "Total should reflect article count"
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  private
    def stub_content_extraction
      mock_content = {
        title: "Fetched Title",
        content_html: "<p>Fetched content</p>",
        content_md: "Fetched content",
        word_count: 2,
        published: Date.today
      }

      WebProcessor.define_singleton_method(:extract_article_content) do |_url|
        mock_content
      end
    end
end
