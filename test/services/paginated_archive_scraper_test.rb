require "test_helper"

class PaginatedArchiveScraperTest < ActiveSupport::TestCase
  setup do
    @base_url = "https://example.com/blog"
    @origin = "https://example.com"
  end

  test "iterates through pages with rel=next link" do
    page1_html = <<~HTML
      <html>
        <head><link rel="next" href="/blog/page/2"></head>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <article><a href="/posts/two">Post Two</a></article>
        </body>
      </html>
    HTML

    page2_html = <<~HTML
      <html>
        <head></head>
        <body>
          <article><a href="/posts/three">Post Three</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/2").to_return(body: page2_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    pages = []

    scraper.each_page do |page_number, page_url, _html, articles_data|
      pages << { page: page_number, url: page_url, articles: articles_data.length }
    end

    assert_equal 2, pages.length
    assert_equal 1, pages[0][:page]
    assert_equal @base_url, pages[0][:url]
    assert_equal 2, pages[1][:page]
    assert scraper.completed?
  end

  test "finds next link in pagination container" do
    page1_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <nav class="pagination">
            <a href="/blog?page=2">Next</a>
          </nav>
        </body>
      </html>
    HTML

    page2_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/two">Post Two</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog?page=2").to_return(body: page2_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page do |_page_number, _page_url, _html, _articles_data|
      page_count += 1
    end

    assert_equal 2, page_count
    assert scraper.completed?
  end

  test "finds next link with 'Older' text" do
    page1_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <a href="/blog/page/2">Older posts</a>
        </body>
      </html>
    HTML

    page2_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/two">Post Two</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/2").to_return(body: page2_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page { page_count += 1 }

    assert_equal 2, page_count
  end

  test "finds next link with anchor rel=next" do
    page1_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <a rel="next" href="/blog/page/2">Page 2</a>
        </body>
      </html>
    HTML

    page2_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/two">Post Two</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/2").to_return(body: page2_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page { page_count += 1 }

    assert_equal 2, page_count
  end

  test "finds next page by page number in pagination container" do
    page1_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <nav class="pagination">
            <span>1</span>
            <a href="/blog/page/2">2</a>
            <a href="/blog/page/3">3</a>
          </nav>
        </body>
      </html>
    HTML

    page2_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/two">Post Two</a></article>
          <nav class="pagination">
            <a href="/blog">1</a>
            <span>2</span>
            <a href="/blog/page/3">3</a>
          </nav>
        </body>
      </html>
    HTML

    page3_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/three">Post Three</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/2").to_return(body: page2_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/3").to_return(body: page3_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page { page_count += 1 }

    assert_equal 3, page_count
    assert scraper.completed?
  end

  test "stops when no next page found" do
    page_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page { page_count += 1 }

    assert_equal 1, page_count
    assert scraper.completed?
  end

  test "stops on fetch error" do
    page1_html = <<~HTML
      <html>
        <head><link rel="next" href="/blog/page/2"></head>
        <body>
          <article><a href="/posts/one">Post One</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/2").to_return(status: 500)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page { page_count += 1 }

    assert_equal 1, page_count
    assert_not scraper.completed?
    assert_not_nil scraper.fetch_error
  end

  test "rejects off-origin next links" do
    page_html = <<~HTML
      <html>
        <head><link rel="next" href="https://evil.com/trap"></head>
        <body>
          <article><a href="/posts/one">Post One</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page { page_count += 1 }

    assert_equal 1, page_count
    assert scraper.completed?  # Completed because no valid next link
  end

  test "handles query string pagination" do
    page1_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <a rel="next" href="/blog?p=2">Next</a>
        </body>
      </html>
    HTML

    page2_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/two">Post Two</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog?p=2").to_return(body: page2_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page { page_count += 1 }

    assert_equal 2, page_count
  end

  test "extract_page_number from various URL patterns" do
    assert_equal 2, PaginatedArchiveScraper.extract_page_number("/blog/page/2")
    assert_equal 3, PaginatedArchiveScraper.extract_page_number("/blog?page=3")
    assert_equal 4, PaginatedArchiveScraper.extract_page_number("/blog?p=4")
    assert_equal 5, PaginatedArchiveScraper.extract_page_number("/blog?paged=5")

    # Offset patterns return nil (not a simple page number)
    assert_nil PaginatedArchiveScraper.extract_page_number("/blog?offset=20")
    assert_nil PaginatedArchiveScraper.extract_page_number("/blog?start=10")

    # Cursor patterns return nil
    assert_nil PaginatedArchiveScraper.extract_page_number("/blog?after=abc123")
    assert_nil PaginatedArchiveScraper.extract_page_number("/blog?cursor=xyz")

    # No pagination in URL
    assert_nil PaginatedArchiveScraper.extract_page_number("/blog")
    assert_nil PaginatedArchiveScraper.extract_page_number("")
    assert_nil PaginatedArchiveScraper.extract_page_number(nil)
  end

  test "resolves relative URLs correctly" do
    page1_html = <<~HTML
      <html>
        <head><link rel="next" href="page/2"></head>
        <body>
          <article><a href="/posts/one">Post One</a></article>
        </body>
      </html>
    HTML

    page2_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/two">Post Two</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/page/2").to_return(body: page2_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    urls = []

    scraper.each_page { |_num, url, _html, _articles| urls << url }

    assert_equal 2, urls.length
    assert_equal "https://example.com/page/2", urls[1]
  end

  test "infers origin from start_url when not provided" do
    scraper = PaginatedArchiveScraper.new(start_url: "https://blog.example.com/archive")

    assert_equal "https://blog.example.com", scraper.origin
  end

  test "finds next page link by id or title attribute when link has no text" do
    page1_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a></article>
          <a href="https://example.com/blog/page/2/" id="paginator-next" title="Next">
            <i class="icon"></i>
          </a>
        </body>
      </html>
    HTML

    page2_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/two">Post Two</a></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page1_html, status: 200)
    stub_request(:get, "https://example.com/blog/page/2/").to_return(body: page2_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    page_count = 0

    scraper.each_page { page_count += 1 }

    assert_equal 2, page_count
    assert scraper.completed?
  end

  test "extracts articles via WebProcessor" do
    page_html = <<~HTML
      <html>
        <body>
          <article><a href="/posts/one">Post One</a><time>2024-01-01</time></article>
          <article><a href="/posts/two">Post Two</a><time>2024-01-02</time></article>
          <article><a href="/posts/three">Post Three</a><time>2024-01-03</time></article>
          <article><a href="/posts/four">Post Four</a><time>2024-01-04</time></article>
          <article><a href="/posts/five">Post Five</a><time>2024-01-05</time></article>
        </body>
      </html>
    HTML

    stub_request(:get, @base_url).to_return(body: page_html, status: 200)

    scraper = PaginatedArchiveScraper.new(start_url: @base_url, origin: @origin)
    articles_found = 0

    scraper.each_page do |_num, _url, _html, articles_data|
      articles_found = articles_data.length
    end

    assert articles_found >= 5, "Should extract at least 5 articles"
  end
end
