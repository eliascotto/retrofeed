require "test_helper"

class ProcessWebsiteJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:test_user)
    # Use a unique domain that doesn't conflict with fixtures
    @archive_url = "https://newblog.example.org/archive"
    ContentErrorGroup.delete_all
  end

  test "job is enqueued on default queue" do
    assert_equal :default, ProcessWebsiteJob.new.queue_name.to_sym
  end

  test "runs detection for new website and delegates to CrawlArchiveJob with metadata" do
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
      assert_enqueued_with(
        job: CrawlArchiveJob,
        args: [
          @archive_url,
          { detection_method: "user_provided", confidence_score: 1.0, pagination_detected: false }
        ]
      ) do
        ProcessWebsiteJob.perform_now(@archive_url)
      end
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "skips detection for existing website and uses stored archive_url" do
    original_interval = WebProcessor.archive_interval
    WebProcessor.instance_variable_set(:@archive_interval, 14.days)

    archive_url = "https://existingblog.example.org/archive"

    Website.create!(
      domain: "existingblog.example.org",
      archive_url: "https://existingblog.example.org/blog",
      archive_detection_method: "known_path",
      archive_confidence_score: 0.9,
      archive_paginated: false,
      last_crawled_at: 1.hour.ago
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| raise "Detection should not be called" }

    begin
      assert_no_enqueued_jobs(only: CrawlArchiveJob) do
        ProcessWebsiteJob.perform_now(archive_url)
      end
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
      WebProcessor.instance_variable_set(:@archive_interval, original_interval)
    end
  end

  test "validates URL before delegating" do
    # Use a blank URL which is definitely invalid
    invalid_url = ""

    assert_raises UrlUtils::InvalidUrlError do
      ProcessWebsiteJob.perform_now(invalid_url)
    end
  end

  test "records url validation error when invalid" do
    invalid_url = "invalid-url"
    original_validate = UrlUtils.method(:validate_and_normalize_url)
    UrlUtils.define_singleton_method(:validate_and_normalize_url) do |_url|
      raise UrlUtils::InvalidUrlError, "invalid"
    end

    assert_difference -> { ContentErrorGroup.count }, +1 do
      assert_raises UrlUtils::InvalidUrlError do
        ProcessWebsiteJob.perform_now(invalid_url)
      end
    end

    err = ContentErrorGroup.last
    assert_equal "website_url_validate", err.operation
    assert_equal "process", err.phase
  ensure
    UrlUtils.define_singleton_method(:validate_and_normalize_url, original_validate)
  end

  test "raises InvalidArchiveError when detection fails" do
    # Use unique domain to ensure no existing website
    detection_fail_url = "https://faildetect.example.org/archive"

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| raise ArchivePageDetector::DetectionError, "No archive found" }

    begin
      assert_raises WebProcessor::InvalidArchiveError do
        ProcessWebsiteJob.perform_now(detection_fail_url)
      end
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "records detection error when detection fails" do
    # Use unique domain to ensure no existing website
    detection_fail_url = "https://faildetect2.example.org/archive"

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| raise ArchivePageDetector::DetectionError, "No archive found" }

    begin
      assert_difference -> { ContentErrorGroup.count }, +1 do
        assert_raises WebProcessor::InvalidArchiveError do
          ProcessWebsiteJob.perform_now(detection_fail_url)
        end
      end

      err = ContentErrorGroup.last
      assert_equal "website_archive_detect", err.operation
      assert_equal "process", err.phase
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "uses validated_url when existing website has no archive_url" do
    # Use a unique domain for this test
    no_archive_url = "https://noarchive.example.org/archive"

    # Create an existing website without an archive_url
    Website.create!(
      domain: UrlUtils.extract_domain(no_archive_url),
      archive_url: nil,
      archive_detection_method: nil,
      archive_confidence_score: nil,
      archive_paginated: false
    )

    detection_result = ArchivePageDetector::Result.new(
      url: no_archive_url,
      method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false,
      notes: nil
    )

    original_detect = ArchivePageDetector.method(:detect)
    ArchivePageDetector.define_singleton_method(:detect) { |_url| detection_result }

    begin
      assert_enqueued_with(job: CrawlArchiveJob) do
        ProcessWebsiteJob.perform_now(no_archive_url)
      end
    ensure
      ArchivePageDetector.define_singleton_method(:detect, original_detect)
    end
  end

  test "skips recently crawled websites" do
    original_interval = WebProcessor.archive_interval
    WebProcessor.instance_variable_set(:@archive_interval, 6.days)

    archive_url = "https://overreacted.io/"

    begin
      Website.create!(
        domain: "overreacted.io",
        archive_url: archive_url,
        last_crawled_at: 1.day.ago
      )

      assert_no_enqueued_jobs(only: CrawlArchiveJob) do
        ProcessWebsiteJob.perform_now(archive_url)
      end
    ensure
      WebProcessor.instance_variable_set(:@archive_interval, original_interval)
    end
  end
end
