require "test_helper"

class PaginateArchiveJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @website = Website.create!(
      domain: "example.com",
      name: "Example Blog",
      archive_url: "https://example.com/blog",
      archive_paginated: true,
      last_crawled_at: 1.hour.ago,
      processing_status: "extracting"
    )
    ContentErrorGroup.delete_all
  end

  test "job is enqueued on archive_paginator queue" do
    assert_equal :archive_paginator, PaginateArchiveJob.new.queue_name.to_sym
  end

  test "skips pagination when website not eligible" do
    @website.update!(archive_paginated: false)

    assert_no_difference "Article.count" do
      PaginateArchiveJob.perform_now(@website.id)
    end
  end

  test "skips pagination when recently completed" do
    @website.update!(pagination_completed_at: 1.hour.ago)

    assert_no_difference "Article.count" do
      PaginateArchiveJob.perform_now(@website.id)
    end
  end

  test "creates articles from paginated pages" do
    # Build pages with 5+ articles each to pass archive validation
    page2_html = build_archive_html([
      { url: "/posts/page2-post1", title: "Page 2 Post 1" },
      { url: "/posts/page2-post2", title: "Page 2 Post 2" },
      { url: "/posts/page2-post3", title: "Page 2 Post 3" },
      { url: "/posts/page2-post4", title: "Page 2 Post 4" },
      { url: "/posts/page2-post5", title: "Page 2 Post 5" }
    ], next_page: "/blog/page/3")

    page3_html = build_archive_html([
      { url: "/posts/page3-post1", title: "Page 3 Post 1" },
      { url: "/posts/page3-post2", title: "Page 3 Post 2" },
      { url: "/posts/page3-post3", title: "Page 3 Post 3" },
      { url: "/posts/page3-post4", title: "Page 3 Post 4" },
      { url: "/posts/page3-post5", title: "Page 3 Post 5" }
    ])

    # Stub page 1 -> page 2 -> page 3
    stub_request(:get, "https://example.com/blog")
      .to_return(body: build_archive_html([
        { url: "/posts/page1-post1", title: "Page 1 Post 1" },
        { url: "/posts/page1-post2", title: "Page 1 Post 2" },
        { url: "/posts/page1-post3", title: "Page 1 Post 3" },
        { url: "/posts/page1-post4", title: "Page 1 Post 4" },
        { url: "/posts/page1-post5", title: "Page 1 Post 5" }
      ], next_page: "/blog/page/2"), status: 200)

    stub_request(:get, "https://example.com/blog/page/2")
      .to_return(body: page2_html, status: 200)

    stub_request(:get, "https://example.com/blog/page/3")
      .to_return(body: page3_html, status: 200)

    # Skip page 1, process pages 2 and 3 (5 + 5 = 10 articles)
    assert_difference "Article.count", 10 do
      PaginateArchiveJob.perform_now(@website.id)
    end

    @website.reload
    assert_equal "completed", @website.pagination_halted_reason
    assert_not_nil @website.pagination_completed_at
  end

  test "halts on page limit" do
    @website.update!(pagination_page_limit: 2)

    # Build pages that would exceed limit
    page1_html = build_archive_html(
      [ { url: "/posts/p1", title: "P1" } ],
      next_page: "/blog/page/2"
    )
    page2_html = build_archive_html(
      [ { url: "/posts/p2", title: "P2" } ],
      next_page: "/blog/page/3"
    )
    page3_html = build_archive_html(
      [ { url: "/posts/p3", title: "P3" } ],
      next_page: "/blog/page/4"
    )

    stub_request(:get, "https://example.com/blog").to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/2").to_return(body: page2_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/3").to_return(body: page3_html, status: 200)

    PaginateArchiveJob.perform_now(@website.id)

    @website.reload
    assert_equal "page_limit", @website.pagination_halted_reason
  end

  test "halts on trap detection - circular URL" do
    # Page 2 links back to itself
    page2_html = <<~HTML
      <html>
        <head><link rel="next" href="/blog/page/2"></head>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
          <article><a href="/posts/three">Post Three</a></article>
          <article><a href="/posts/four">Post Four</a></article>
          <article><a href="/posts/five">Post Five</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, "https://example.com/blog")
      .to_return(body: build_archive_html([], next_page: "/blog/page/2"), status: 200)

    stub_request(:get, "https://example.com/blog/page/2")
      .to_return(body: page2_html, status: 200)

    PaginateArchiveJob.perform_now(@website.id)

    @website.reload
    assert_equal "trap_detected", @website.pagination_halted_reason

    # Should record an error with severity warn
    error = ContentErrorGroup.last
    assert_not_nil error
    assert_equal "warn", error.severity
    assert_match(/trap_detected/, error.operation)
  end

  test "halts on fetch error" do
    stub_request(:get, "https://example.com/blog")
      .to_return(body: build_archive_html([], next_page: "/blog/page/2"), status: 200)

    stub_request(:get, "https://example.com/blog/page/2")
      .to_return(status: 500)

    PaginateArchiveJob.perform_now(@website.id)

    @website.reload
    assert_equal "error", @website.pagination_halted_reason
  end

  test "marks website as completed after pagination" do
    # Must start in extracting - CrawlArchiveJob sets this before enqueueing PaginateArchiveJob
    website = Website.create!(
      domain: "example-nocontent.com",
      archive_url: "https://example-nocontent.com/blog",
      archive_paginated: true,
      last_crawled_at: 1.hour.ago,
      processing_status: "extracting"
    )

    page2_html = build_archive_html([ { url: "/posts/new-post", title: "New Post" } ])

    stub_request(:get, "https://example-nocontent.com/blog")
      .to_return(body: build_archive_html([], next_page: "/blog/page/2"), status: 200)
    stub_request(:get, "https://example-nocontent.com/blog/page/2")
      .to_return(body: page2_html, status: 200)

    PaginateArchiveJob.perform_now(website.id)

    website.reload
    assert_equal "completed", website.processing_status
  end

  test "does not create duplicate articles" do
    # Create an existing article
    Article.create!(
      website: @website,
      url: "https://example.com/posts/existing",
      title: "Existing Post"
    )

    page2_html = build_archive_html([
      { url: "/posts/existing", title: "Existing Post" },  # duplicate
      { url: "/posts/new-post1", title: "New Post 1" },
      { url: "/posts/new-post2", title: "New Post 2" },
      { url: "/posts/new-post3", title: "New Post 3" },
      { url: "/posts/new-post4", title: "New Post 4" }
    ])

    stub_request(:get, "https://example.com/blog")
      .to_return(body: build_archive_html([
        { url: "/posts/page1-1", title: "P1" },
        { url: "/posts/page1-2", title: "P2" },
        { url: "/posts/page1-3", title: "P3" },
        { url: "/posts/page1-4", title: "P4" },
        { url: "/posts/page1-5", title: "P5" }
      ], next_page: "/blog/page/2"), status: 200)

    stub_request(:get, "https://example.com/blog/page/2")
      .to_return(body: page2_html, status: 200)

    # Should create 4 new articles from page 2 (existing one is skipped)
    assert_difference "Article.count", 4 do
      PaginateArchiveJob.perform_now(@website.id)
    end
  end

  test "updates pagination progress fields" do
    page2_html = build_archive_html([
      { url: "/posts/p1", title: "P1" }
    ], next_page: "/blog/page/3")

    page3_html = build_archive_html([
      { url: "/posts/p2", title: "P2" }
    ])

    stub_request(:get, "https://example.com/blog")
      .to_return(body: build_archive_html([], next_page: "/blog/page/2"), status: 200)

    stub_request(:get, "https://example.com/blog/page/2")
      .to_return(body: page2_html, status: 200)

    stub_request(:get, "https://example.com/blog/page/3")
      .to_return(body: page3_html, status: 200)

    PaginateArchiveJob.perform_now(@website.id)

    @website.reload
    assert_equal 3, @website.pagination_last_page_scraped
    assert_equal 3, @website.pagination_total_pages_found
    assert_not_nil @website.pagination_completed_at
  end

  test "handles website not found gracefully" do
    assert_nothing_raised do
      PaginateArchiveJob.perform_now(999999)
    end
  end

  private

  def build_archive_html(articles, next_page: nil)
    article_html = articles.map do |a|
      "<article><a href=\"#{a[:url]}\">#{a[:title]}</a><time>2024-01-01</time></article>"
    end.join("\n")

    next_link = next_page ? "<link rel=\"next\" href=\"#{next_page}\">" : ""

    <<~HTML
      <html>
        <head>#{next_link}</head>
        <body>
          #{article_html}
        </body>
      </html>
    HTML
  end
end
