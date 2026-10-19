require "test_helper"

class ArticleExtractorTest < ActiveSupport::TestCase
  # Create a test class that includes the ArticleExtractor module
  class TestExtractor
    include WebProcessor::ArticleExtractor
  end

  setup do
    @extractor = TestExtractor.new
  end

  # Tests for article_like_path? method
  test "article_like_path? returns false for blank path" do
    assert_not @extractor.article_like_path?(nil)
    assert_not @extractor.article_like_path?("")
  end

  test "article_like_path? returns false for root path" do
    assert_not @extractor.article_like_path?("/")
  end

  test "article_like_path? returns false when path equals base_path" do
    assert_not @extractor.article_like_path?("/blog", "/blog")
  end

  test "article_like_path? returns true for valid article paths" do
    assert @extractor.article_like_path?("/blog/my-article", "/blog")
    assert @extractor.article_like_path?("/posts/2024/01/hello", "/posts")
    assert @extractor.article_like_path?("/writing/essay-title", "/")
  end

  test "article_like_path? returns false for excluded patterns" do
    assert_not @extractor.article_like_path?("/category/tech")
    assert_not @extractor.article_like_path?("/tag/ruby")
    assert_not @extractor.article_like_path?("/about")
    assert_not @extractor.article_like_path?("/about/")
    assert_not @extractor.article_like_path?("/page/2")
    assert_not @extractor.article_like_path?("/feed")
  end

  test "article_like_path? allows path that only contains pattern as substring (e.g. about-the-passion)" do
    assert @extractor.article_like_path?("/blog/about-chat-control", "/blog")
    assert @extractor.article_like_path?("/about-the-passion", "/")
  end

  # Trailing slash normalization tests - these are the key tests for the fix
  test "article_like_path? excludes path with trailing slash when base_path has none" do
    # When archive URL is /blog (no trailing slash), a link to /blog/ should be excluded
    # because it's the same page (just with trailing slash)
    assert_not @extractor.article_like_path?("/blog/", "/blog"),
               "Path '/blog/' should be excluded when base_path is '/blog' (same page with trailing slash)"
  end

  test "article_like_path? excludes path without trailing slash when base_path has one" do
    # When archive URL is /blog/ (with trailing slash), a link to /blog should be excluded
    # because it's the same page (just without trailing slash)
    assert_not @extractor.article_like_path?("/blog", "/blog/"),
               "Path '/blog' should be excluded when base_path is '/blog/' (same page without trailing slash)"
  end

  test "article_like_path? handles root path variations" do
    # Root with trailing slash variations
    assert_not @extractor.article_like_path?("/", "/")
    assert_not @extractor.article_like_path?("/", "")
  end

  test "article_like_path? still allows sub-paths after trailing slash normalization" do
    # Ensure we don't over-exclude: /blog/article should still be valid
    assert @extractor.article_like_path?("/blog/my-post", "/blog")
    assert @extractor.article_like_path?("/blog/my-post", "/blog/")
    assert @extractor.article_like_path?("/blog/my-post/", "/blog")
    assert @extractor.article_like_path?("/blog/my-post/", "/blog/")
  end

  # Tests for extract_table_row_data with archives whose cells carry no
  # title/date class. patshaughnessy.net renders rows as
  #   <td id="date">November 2025</td><td><a href="...">Title</a></td>
  # so the title cell has no class (the link must be found by article_like_path?)
  # and the date cell is identified by id, not class.
  def table_row(inner)
    Nokogiri::HTML("<table><tbody>#{inner}</tbody></table>").css("tr").first
  end

  test "extract_table_row_data picks the article-like link from an unclassed title cell" do
    row = table_row(<<~HTML)
      <tr>
        <td id="date">November 2025</td>
        <td><a href="2025/11/17/compiling-ruby-to-machine-language">Compiling Ruby To Machine Language</a></td>
      </tr>
    HTML

    data = @extractor.extract_table_row_data(row, "https://patshaughnessy.net/archive")

    assert_equal "Compiling Ruby To Machine Language", data[:title]
    assert data[:url].end_with?("/2025/11/17/compiling-ruby-to-machine-language")
    assert_equal Date.new(2025, 11, 17), data[:date]
  end

  test "extract_table_row_data reads the date from an id-based date cell when the url has none" do
    row = table_row(<<~HTML)
      <tr>
        <td id="date">2024-01-15</td>
        <td><a href="/posts/hello-world">Hello World</a></td>
      </tr>
    HTML

    data = @extractor.extract_table_row_data(row, "https://example.com/archive")

    assert_equal "Hello World", data[:title]
    assert_equal "https://example.com/posts/hello-world", data[:url]
    assert_equal Date.new(2024, 1, 15), data[:date]
  end
end
