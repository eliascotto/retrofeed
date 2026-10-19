require "test_helper"

class ArchivePageDetector::SimonWillisonDetectorTest < ActiveSupport::TestCase
  setup do
    @year_page_html = <<~HTML
      <div id="wrapper">
        <div id="primary">
          <h2 class="archive-h2">Archive for 2026</h2>
          <div class="entry">
            <ul>
              <li><strong><a href="/2026/Jan/">January</a></strong> - 5 entries, 18 links, 9 quotes, 3 notes
                <ul>
                  <li>1st: <a href="/2026/Jan/1/gisthost/">Introducing gisthost.github.io</a></li>
                  <li>8th: <a href="/2026/Jan/8/llm-predictions-for-2026/">LLM predictions for 2026, shared with Oxide and Friends</a></li>
                  <li>9th: <a href="/2026/Jan/9/sprites-dev/">Fly's new Sprites.dev addresses both developer sandboxes and API sandboxes at the same time</a></li>
                  <li>11th: <a href="/2026/Jan/11/answers/">My answers to the questions I posed about porting open source code with LLMs</a></li>
                  <li>12th: <a href="/2026/Jan/12/claude-cowork/">First impressions of Claude Cowork, Anthropic's general agent</a></li>
                </ul>
              </li>
            </ul>
          </div>
        </div>
      </div>
    HTML

    @month_page_html = <<~HTML
      <html>
        <head><title>Simon Willison's Weblog: January 2024</title></head>
        <body>
          <h1>January 2024</h1>
          <ul>
            <li><a href="/2024/Jan/15/first-post/">15th: First Post of the Year</a></li>
            <li><a href="/2024/Jan/20/second-post/">20th: Second Post</a></li>
            <li><a href="/2024/Jan/25/third-post/">25th: Third Post</a></li>
          </ul>
        </body>
      </html>
    HTML
  end

  # Detection tests

  test "detect returns year URL when given year page" do
    stub_request(:get, "https://simonwillison.net/2024/")
      .to_return(body: @year_page_html, status: 200)

    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/2024/")
    result = detector.detect

    assert_equal "https://simonwillison.net/2024/", result.url
    assert_equal "custom_simonwillison", result.method
    assert_equal 1.0, result.confidence_score
    assert result.pagination_detected
  end

  test "detect extracts year from article URL and returns year page" do
    stub_request(:head, %r{simonwillison\.net/2024/$})
      .to_return(status: 200)

    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/2024/Jan/15/some-article/")
    result = detector.detect

    assert_equal "https://simonwillison.net/2024/", result.url
    assert_equal "custom_simonwillison", result.method
    assert_equal 1.0, result.confidence_score
  end

  test "detect extracts year from month URL and returns year page" do
    stub_request(:head, %r{simonwillison\.net/2024/$})
      .to_return(status: 200)

    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/2024/Mar/")
    result = detector.detect

    assert_equal "https://simonwillison.net/2024/", result.url
    assert_equal "custom_simonwillison", result.method
  end

  test "detect defaults to current year for homepage" do
    current_year = Time.current.year
    stub_request(:head, "https://simonwillison.net/#{current_year}/")
      .to_return(status: 200)

    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/")
    result = detector.detect

    assert_equal "https://simonwillison.net/#{current_year}/", result.url
    assert_equal "custom_simonwillison", result.method
  end

  test "detect falls back to previous year if current year not available" do
    current_year = Time.current.year
    stub_request(:head, "https://simonwillison.net/#{current_year}/")
      .to_return(status: 404)

    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/")
    result = detector.detect

    assert_equal "https://simonwillison.net/#{current_year - 1}/", result.url
    assert_equal 0.95, result.confidence_score
  end

  # Article extraction tests

  test "extract_articles from month page extracts articles with dates" do
    html = Nokogiri::HTML(@month_page_html)
    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/2024/Jan/")

    articles = detector.extract_articles(html, "https://simonwillison.net/2024/Jan/")

    assert_equal 3, articles.length

    first_article = articles.find { |a| a[:url].include?("first-post") }
    assert_equal "First Post of the Year", first_article[:title]
    assert_equal "https://simonwillison.net/2024/Jan/15/first-post/", first_article[:url]
    assert_equal Date.new(2024, 1, 15), first_article[:date]

    second_article = articles.find { |a| a[:url].include?("second-post") }
    assert_equal "Second Post", second_article[:title]
    assert_equal Date.new(2024, 1, 20), second_article[:date]
  end

  test "extract_articles from year page extracts articles directly" do
    # No stubs needed - year page contains articles directly, no month pages are fetched
    # WebMock will fail if any HTTP requests are made

    html = Nokogiri::HTML(@year_page_html)
    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/2026/")

    articles = detector.extract_articles(html, "https://simonwillison.net/2026/")

    # Verify no month page requests were made
    assert_not_requested :get, %r{simonwillison\.net/2026/Jan/$}
    assert_not_requested :get, %r{simonwillison\.net/2026/Feb/$}
    assert_not_requested :get, %r{simonwillison\.net/2026/Mar/$}

    # Should have all 5 articles from the year page
    assert_equal 5, articles.length

    # Verify first article
    gisthost = articles.find { |a| a[:url].include?("gisthost") }
    assert_equal "Introducing gisthost.github.io", gisthost[:title]
    assert_equal "https://simonwillison.net/2026/Jan/1/gisthost/", gisthost[:url]
    assert_equal Date.new(2026, 1, 1), gisthost[:date]

    # Verify second article
    llm_predictions = articles.find { |a| a[:url].include?("llm-predictions") }
    assert_equal "LLM predictions for 2026, shared with Oxide and Friends", llm_predictions[:title]
    assert_equal Date.new(2026, 1, 8), llm_predictions[:date]

    # Verify third article
    sprites = articles.find { |a| a[:url].include?("sprites-dev") }
    assert_equal "Fly's new Sprites.dev addresses both developer sandboxes and API sandboxes at the same time", sprites[:title]
    assert_equal Date.new(2026, 1, 9), sprites[:date]

    # Verify fourth article
    answers = articles.find { |a| a[:url].include?("answers") }
    assert_equal "My answers to the questions I posed about porting open source code with LLMs", answers[:title]
    assert_equal Date.new(2026, 1, 11), answers[:date]

    # Verify fifth article
    claude_cowork = articles.find { |a| a[:url].include?("claude-cowork") }
    assert_equal "First impressions of Claude Cowork, Anthropic's general agent", claude_cowork[:title]
    assert_equal Date.new(2026, 1, 12), claude_cowork[:date]
  end

  test "extract_articles handles relative URLs" do
    html = Nokogiri::HTML(@month_page_html)
    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/2024/Jan/")

    articles = detector.extract_articles(html, "https://simonwillison.net/2024/Jan/")

    articles.each do |article|
      assert article[:url].start_with?("https://simonwillison.net/")
    end
  end

  test "extract_articles skips non-article links" do
    html_with_mixed_links = <<~HTML
      <html>
        <body>
          <a href="/2024/Jan/15/real-article/">15th: Real Article</a>
          <a href="/about">About</a>
          <a href="/2024/Jan/">January</a>
          <a href="/feed">RSS</a>
        </body>
      </html>
    HTML

    html = Nokogiri::HTML(html_with_mixed_links)
    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/2024/Jan/")

    articles = detector.extract_articles(html, "https://simonwillison.net/2024/Jan/")

    assert_equal 1, articles.length
    assert_equal "Real Article", articles.first[:title]
  end

  # URL pattern tests

  test "correctly identifies year URLs" do
    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/")

    assert detector.send(:year_url?, "https://simonwillison.net/2024/")
    assert detector.send(:year_url?, "https://simonwillison.net/2024")
    refute detector.send(:year_url?, "https://simonwillison.net/2024/Jan/")
    refute detector.send(:year_url?, "https://simonwillison.net/2024/Jan/15/slug/")
  end

  test "correctly identifies month URLs" do
    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/")

    assert detector.send(:month_url?, "https://simonwillison.net/2024/Jan/")
    assert detector.send(:month_url?, "https://simonwillison.net/2024/Jan")
    assert detector.send(:month_url?, "https://simonwillison.net/2024/Dec/")
    refute detector.send(:month_url?, "https://simonwillison.net/2024/")
    refute detector.send(:month_url?, "https://simonwillison.net/2024/Jan/15/slug/")
  end

  test "correctly identifies article URLs" do
    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/")

    assert detector.send(:article_url?, "https://simonwillison.net/2024/Jan/15/some-article/")
    assert detector.send(:article_url?, "https://simonwillison.net/2024/Jan/15/some-article")
    assert detector.send(:article_url?, "https://simonwillison.net/2010/Aug/24/what-is-the-history/")
    refute detector.send(:article_url?, "https://simonwillison.net/2024/Jan/")
    refute detector.send(:article_url?, "https://simonwillison.net/2024/")
  end

  test "extracts date from article URL" do
    detector = ArchivePageDetector::SimonWillisonDetector.new("https://simonwillison.net/")

    date = detector.send(:extract_date_from_article_url, "https://simonwillison.net/2024/Jan/15/some-article/")
    assert_equal Date.new(2024, 1, 15), date

    date = detector.send(:extract_date_from_article_url, "https://simonwillison.net/2010/Aug/24/what-is-the-history/")
    assert_equal Date.new(2010, 8, 24), date
  end

  # Integration with ArchivePageDetector

  test "ArchivePageDetector uses custom detector for simonwillison.net" do
    current_year = Time.current.year
    stub_request(:head, "https://simonwillison.net/#{current_year}/")
      .to_return(status: 200)

    result = ArchivePageDetector.detect("https://simonwillison.net/")

    assert_equal "https://simonwillison.net/#{current_year}/", result.url
    assert_equal "custom_simonwillison", result.method
  end

  # Integration with WebProcessor

  test "WebProcessor uses custom extraction for simonwillison.net" do
    html = Nokogiri::HTML(@month_page_html)

    result = WebProcessor.extract_articles_from_archive(html, "https://simonwillison.net/2024/Jan/")
    articles = result[:articles]

    assert_equal 3, articles.length
    assert articles.all? { |a| a[:title].present? }
    assert articles.all? { |a| a[:url].start_with?("https://simonwillison.net/") }
  end
end
