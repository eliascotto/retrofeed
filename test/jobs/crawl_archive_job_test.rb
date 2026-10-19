require "test_helper"

class CrawlArchiveJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:test_user)
    @archive_url = "https://overreacted.io/"
    @html_fixture_path = Rails.root.join("test", "fixtures", "websites", "overreacted", "archive.html")
    ContentErrorGroup.delete_all
  end

  test "job is enqueued on archive_crawler queue" do
    assert_equal :archive_crawler, CrawlArchiveJob.new.queue_name.to_sym
  end

  test "creates website record from archive page" do
    stub_archive_request(@archive_url, @html_fixture_path)

    assert_difference "Website.count", 1 do
      # Only run the archive job, not the content fetching jobs
      CrawlArchiveJob.perform_now(@archive_url)
    end

    website = Website.find_by(domain: "overreacted.io")
    assert_not_nil website
    assert_not_nil website.last_crawled_at
    assert_equal @archive_url, website.archive_url
  end

  test "creates article records from archive" do
    stub_archive_request(@archive_url, @html_fixture_path)

    perform_enqueued_jobs(only: CrawlArchiveJob) do
      CrawlArchiveJob.perform_now(@archive_url)
    end

    website = Website.find_by(domain: "overreacted.io")
    assert website.articles.count > 0, "Should have created articles"
  end

  test "marks website as completed when no pagination" do
    stub_archive_request(@archive_url, @html_fixture_path)

    CrawlArchiveJob.perform_now(@archive_url)

    website = Website.find_by(domain: "overreacted.io")
    assert_equal "completed", website.processing_status
  end

  test "raises InvalidArchiveError for non-archive pages" do
    non_archive_html = "<html><body><h1>Not an archive</h1></body></html>"
    stub_request(:get, @archive_url).to_return(body: non_archive_html, status: 200)

    assert_raises WebProcessor::InvalidArchiveError do
      CrawlArchiveJob.perform_now(@archive_url)
    end
  end

  test "raises InvalidArchiveError on network failure" do
    stub_request(:get, @archive_url).to_timeout

    assert_raises WebProcessor::InvalidArchiveError do
      CrawlArchiveJob.perform_now(@archive_url)
    end
  end

  test "records fetch error when WebFetcher raises" do
    original_fetch = WebFetcher.method(:fetch)
    WebFetcher.define_singleton_method(:fetch) do |_url|
      raise WebFetcher::FetchError.new("HTTP 500", http_status: 500, url: @archive_url)
    end

    assert_difference -> { ContentErrorGroup.count }, +1 do
      assert_raises WebProcessor::InvalidArchiveError do
        CrawlArchiveJob.perform_now(@archive_url)
      end
    end

    err = ContentErrorGroup.last
    assert_equal "website_archive_fetch", err.operation
    assert_equal 500, err.http_status
    assert_equal "overreacted.io", err.domain
  ensure
    WebFetcher.define_singleton_method(:fetch, original_fetch)
  end

  test "records archive validation error when archive is invalid" do
    stub_request(:get, @archive_url).to_return(body: "<html><body>not archive</body></html>", status: 200)

    original_contains = WebProcessor.method(:contains_valid_archive?)
    WebProcessor.define_singleton_method(:contains_valid_archive?) { |_html, _url, **_opts| false }

    assert_difference -> { ContentErrorGroup.count }, +1 do
      assert_raises WebProcessor::InvalidArchiveError do
        CrawlArchiveJob.perform_now(@archive_url)
      end
    end

    err = ContentErrorGroup.last
    assert_equal "website_archive_validate", err.operation
    assert_equal "overreacted.io", err.domain
  ensure
    WebProcessor.define_singleton_method(:contains_valid_archive?, original_contains)
  end

  test "handles duplicate articles gracefully" do
    stub_archive_request(@archive_url, @html_fixture_path)

    # Create the website and an article that will be found during crawl
    Website.create!(
      domain: "overreacted.io",
      archive_url: @archive_url,
      last_crawled_at: 10.days.ago
    )

    # Run - should not fail on duplicates
    assert_nothing_raised do
      CrawlArchiveJob.perform_now(@archive_url)
    end
  end

  test "does not create duplicate articles when archive contains same URL twice" do
    stub_archive_request(@archive_url, @html_fixture_path)

    # Mock extract_articles_from_archive to return duplicate entries (same URL twice)
    # This simulates a malformed archive that lists the same article multiple times
    duplicate_article_url = "https://overreacted.io/a-complete-guide-to-useeffect/"
    duplicate_articles_data = [
      { url: duplicate_article_url, title: "A Complete Guide to useEffect", date: Date.new(2019, 3, 9) },
      { url: duplicate_article_url, title: "A Complete Guide to useEffect", date: Date.new(2019, 3, 9) },
      { url: "https://overreacted.io/how-are-function-components-different-from-classes/", title: "Different Article", date: Date.new(2019, 3, 1) }
    ]

    original_extract = WebProcessor.method(:extract_articles_from_archive)
    WebProcessor.define_singleton_method(:extract_articles_from_archive) do |_html, _url, **_opts|
      { articles: duplicate_articles_data }
    end

    begin
      CrawlArchiveJob.perform_now(@archive_url)

      website = Website.find_by(domain: "overreacted.io")

      # Should have exactly 2 articles, not 3 (the duplicate URL should only create one record)
      assert_equal 2, website.articles.count, "Should create only 2 articles despite 3 entries with duplicate URL"

      # Verify the duplicate URL exists only once
      duplicate_url_count = website.articles.where(url: duplicate_article_url).count
      assert_equal 1, duplicate_url_count, "Duplicate URL should appear only once in database"
    ensure
      WebProcessor.define_singleton_method(:extract_articles_from_archive, original_extract)
    end
  end

  test "persists detection metadata when provided" do
    stub_archive_request(@archive_url, @html_fixture_path)

    CrawlArchiveJob.perform_now(
      @archive_url,
      detection_method: "known_path",
      confidence_score: 0.9,
      pagination_detected: true
    )

    website = Website.find_by(domain: "overreacted.io")
    assert_equal "known_path", website.archive_detection_method
    assert_equal 0.9, website.archive_confidence_score
    assert_equal true, website.archive_paginated
  end

  test "persists user_provided detection method" do
    stub_archive_request(@archive_url, @html_fixture_path)

    CrawlArchiveJob.perform_now(
      @archive_url,
      detection_method: "user_provided",
      confidence_score: 1.0,
      pagination_detected: false
    )

    website = Website.find_by(domain: "overreacted.io")
    assert_equal "user_provided", website.archive_detection_method
    assert_equal 1.0, website.archive_confidence_score
    assert_equal false, website.archive_paginated
  end

  test "enqueues PaginateArchiveJob when pagination is detected" do
    stub_archive_request(@archive_url, @html_fixture_path)

    assert_enqueued_with(job: PaginateArchiveJob) do
      CrawlArchiveJob.perform_now(
        @archive_url,
        pagination_detected: true
      )
    end

    # Verify website was persisted with pagination flag
    website = Website.find_by(domain: "overreacted.io")
    assert_equal true, website.archive_paginated
  end

  test "does not enqueue PaginateArchiveJob when pagination not detected" do
    stub_archive_request(@archive_url, @html_fixture_path)

    assert_no_enqueued_jobs(only: PaginateArchiveJob) do
      CrawlArchiveJob.perform_now(
        @archive_url,
        pagination_detected: false
      )
    end
  end

  test "does not enqueue PaginateArchiveJob when pagination recently completed" do
    stub_archive_request(@archive_url, @html_fixture_path)

    # Create website with recent pagination completion
    Website.create!(
      domain: "overreacted.io",
      archive_url: @archive_url,
      archive_paginated: true,
      pagination_completed_at: 1.hour.ago,
      last_crawled_at: 20.days.ago  # Old enough to allow re-crawl
    )

    assert_no_enqueued_jobs(only: PaginateArchiveJob) do
      CrawlArchiveJob.perform_now(
        @archive_url,
        pagination_detected: true
      )
    end
  end

  test "still creates articles when pagination is detected" do
    stub_archive_request(@archive_url, @html_fixture_path)

    CrawlArchiveJob.perform_now(
      @archive_url,
      pagination_detected: true
    )

    website = Website.find_by(domain: "overreacted.io")
    assert website.articles.count > 0, "Should still create articles from page 1"
    assert_equal true, website.archive_paginated
  end

  test "extracts and downloads favicon from archive page" do
    # Create an archive page with a favicon link
    html_with_favicon = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Test Archive</title>
        <link rel="icon" href="/favicon.ico">
      </head>
      <body>
        <a href="/post1">Post 1</a>
        <a href="/post2">Post 2</a>
        <a href="/post3">Post 3</a>
        <a href="/post4">Post 4</a>
        <a href="/post5">Post 5</a>
      </body>
      </html>
    HTML

    # Minimal ICO data
    ico_data = "\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00\x04\x00".dup.force_encoding("BINARY")

    # Stub archive and favicon requests
    stub_request(:get, "https://test-favicon.com/archive").to_return(body: html_with_favicon, status: 200)
    stub_request(:get, "https://test-favicon.com/").to_return(body: html_with_favicon, status: 200)
    stub_request(:get, "https://test-favicon.com/favicon.ico").to_return(body: ico_data, status: 200)

    CrawlArchiveJob.perform_now("https://test-favicon.com/archive")

    website = Website.find_by(domain: "test-favicon.com")
    assert_not_nil website
    assert website.favicon.attached?, "Favicon should be attached to website"
  end

  test "continues crawling when favicon download fails" do
    # Create an archive page with a favicon link
    html_with_favicon = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Test Archive</title>
        <link rel="icon" href="/favicon.ico">
      </head>
      <body>
        <a href="/post1">Post 1</a>
        <a href="/post2">Post 2</a>
        <a href="/post3">Post 3</a>
        <a href="/post4">Post 4</a>
        <a href="/post5">Post 5</a>
      </body>
      </html>
    HTML

    # Stub archive request but make favicon request fail
    stub_request(:get, "https://test-no-favicon.com/archive").to_return(body: html_with_favicon, status: 200)
    stub_request(:get, "https://test-no-favicon.com/").to_return(body: html_with_favicon, status: 200)
    stub_request(:get, "https://test-no-favicon.com/favicon.ico").to_return(status: 404)

    # Should not raise even though favicon download fails
    assert_nothing_raised do
      CrawlArchiveJob.perform_now("https://test-no-favicon.com/archive")
    end

    website = Website.find_by(domain: "test-no-favicon.com")
    assert_not_nil website, "Website should still be created"
    assert_not website.favicon.attached?, "Favicon should not be attached when download fails"
  end
end
