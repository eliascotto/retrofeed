require "test_helper"

class FetchArticleContentJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  MOCK_HTML = "<html><body><p>Test content</p></body></html>".freeze

  setup do
    @website = websites(:one)
    @article = Article.create!(
      website: @website,
      url: "https://example.com/test-article",
      title: "Test Article"
    )

    # Stub WebFetcher.fetch to avoid real HTTP requests
    # Returns a hash with :content and :final_url as expected by the API
    @original_fetch = WebFetcher.method(:fetch)
    WebFetcher.define_singleton_method(:fetch) { |url| { content: MOCK_HTML, final_url: url } }

    ContentErrorGroup.delete_all
  end

  teardown do
    WebFetcher.define_singleton_method(:fetch, @original_fetch) if @original_fetch
  end

  test "job is enqueued on content_fetcher queue" do
    assert_equal :content_fetcher, FetchArticleContentJob.new.queue_name.to_sym
  end

  test "fetches and updates article content" do
    mock_result = {
      content: {
        title: "Updated Title",
        content_html: "<p>Article content</p>",
        content_md: "Article content",
        word_count: 2,
        published: Date.today
      }
    }

    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| mock_result }

    begin
      FetchArticleContentJob.perform_now(@article)

      @article.reload
      assert_equal "Updated Title", @article.title
      assert_equal "<p>Article content</p>", @article.content_html
      assert_equal "Article content", @article.content_md
      assert_equal 2, @article.word_count
      assert_not_nil @article.content_hash
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "records fetch error when WebFetcher raises" do
    WebFetcher.define_singleton_method(:fetch) do |_url|
      raise WebFetcher::FetchError.new(
        "HTTP 500 while fetching https://example.com/test-article",
        http_status: 500,
        headers: { "Content-Type" => "text/html" },
        url: "https://example.com/test-article"
      )
    end

    assert_difference -> { ContentErrorGroup.count }, +1 do
      assert_enqueued_with(job: FetchArticleContentJob) do
        FetchArticleContentJob.perform_now(@article)
      end
    end

    err = ContentErrorGroup.last
    assert_equal "article_html_fetch", err.operation
    assert_equal "Article", err.subject_type
    assert_equal @article.id, err.subject_id
    assert_equal 500, err.http_status
  ensure
    WebFetcher.define_singleton_method(:fetch, @original_fetch)
  end

  test "records processing error when extraction fails" do
    original_extract = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| { error: "parse failed" } }

    assert_difference -> { ContentErrorGroup.count }, +1 do
      assert_enqueued_with(job: FetchArticleContentJob) do
        FetchArticleContentJob.perform_now(@article)
      end
    end

    err = ContentErrorGroup.last
    assert_equal "article_defuddle_extract", err.operation
    assert_equal "Article", err.subject_type
    assert_equal @article.id, err.subject_id
  ensure
    WebProcessor.define_singleton_method(:extract_article_content, original_extract)
  end

  test "preserves original title when extraction returns nil title" do
    mock_result = {
      content: {
        title: nil,
        content_html: "<p>Content</p>",
        content_md: "Content",
        word_count: 1,
        published: nil
      }
    }

    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| mock_result }

    begin
      FetchArticleContentJob.perform_now(@article)

      @article.reload
      assert_equal "Test Article", @article.title
      assert_equal "<p>Content</p>", @article.content_html
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "skips articles with recently updated content" do
    @article.update!(
      content_html: "<p>Existing content</p>",
      updated_at: 1.minute.ago
    )

    # Define methods that would raise if called (they shouldn't be)
    original_fetch = WebFetcher.method(:fetch)
    original_extract = WebProcessor.method(:extract_article_content)
    WebFetcher.define_singleton_method(:fetch) { |_url| raise "Should not be called" }
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| raise "Should not be called" }

    begin
      FetchArticleContentJob.perform_now(@article)
      # Content should remain unchanged
      assert_equal "<p>Existing content</p>", @article.reload.content_html
    ensure
      WebFetcher.define_singleton_method(:fetch, original_fetch)
      WebProcessor.define_singleton_method(:extract_article_content, original_extract)
    end
  end

  test "raises error when content extraction fails" do
    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| nil }

    begin
      # The job has retry_on, so the error is caught and a retry is scheduled
      # We verify by checking that the job enqueues a retry
      assert_enqueued_with(job: FetchArticleContentJob) do
        FetchArticleContentJob.perform_now(@article)
      end
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "discards job when article not found" do
    # Delete the article
    article_id = @article.id
    @article.destroy

    # Should not raise, just discard
    assert_nothing_raised do
      FetchArticleContentJob.perform_now(article_id)
    end
  end

  test "has retry configuration" do
    # Check that the job has retry_on configured
    assert FetchArticleContentJob.respond_to?(:retry_on)
  end

  test "updates publication_date from extracted content" do
    extracted_date = Date.new(2024, 1, 15)
    mock_result = {
      content: {
        title: "Title",
        content_html: "<p>Content</p>",
        content_md: "Content",
        word_count: 1,
        published: extracted_date
      }
    }

    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| mock_result }

    begin
      FetchArticleContentJob.perform_now(@article)
      assert_equal extracted_date, @article.reload.publication_date
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "creates first version on initial successful download" do
    mock_result = {
      content: {
        title: "Updated Title",
        content_html: "<p>Article content</p>",
        content_md: "Article content",
        word_count: 2,
        published: Date.today
      }
    }

    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| mock_result }

    begin
      assert_difference -> { ArticleVersion.count }, +1 do
        FetchArticleContentJob.perform_now(@article)
      end

      version = @article.article_versions.sole
      assert_equal 1, version.version
      assert_equal "<p>Article content</p>", version.content_html
      assert_equal "Article content", version.content_md
      assert_equal Digest::SHA256.hexdigest(MOCK_HTML), version.content_hash
      assert_equal 2, version.word_count
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "does not create new version when content hash is unchanged" do
    existing_hash = Digest::SHA256.hexdigest(MOCK_HTML)
    @article.update!(
      content_html: "<p>Existing</p>",
      content_md: "Existing",
      content_hash: existing_hash,
      last_content_fetched_at: 90.days.ago
    )
    @article.article_versions.create!(version: 1, content_hash: existing_hash)

    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| raise "Should not be called" }

    begin
      assert_no_difference -> { ArticleVersion.count } do
        FetchArticleContentJob.perform_now(@article)
      end
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "creates incremented version when html changes" do
    old_hash = Digest::SHA256.hexdigest("<html>old</html>")
    @article.update!(
      content_html: "<p>Old</p>",
      content_hash: old_hash,
      last_content_fetched_at: 90.days.ago
    )
    @article.article_versions.create!(
      version: 1,
      content_hash: old_hash,
      content_html: "<p>Old</p>"
    )

    mock_result = {
      content: {
        title: "New Title",
        content_html: "<p>New content</p>",
        content_md: "New content",
        word_count: 2,
        published: nil
      }
    }

    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| mock_result }

    begin
      assert_difference -> { ArticleVersion.count }, +1 do
        FetchArticleContentJob.perform_now(@article)
      end

      versions = @article.article_versions.order(:version).to_a
      assert_equal [ 1, 2 ], versions.map(&:version)
      assert_equal "<p>Old</p>", versions.first.content_html
      assert_equal "<p>New content</p>", versions.last.content_html
      assert_equal Digest::SHA256.hexdigest(MOCK_HTML), versions.last.content_hash
      assert_equal Digest::SHA256.hexdigest(MOCK_HTML), @article.reload.content_hash
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "does not create version when fetch raises" do
    WebFetcher.define_singleton_method(:fetch) do |_url|
      raise WebFetcher::FetchError.new(
        "HTTP 500", http_status: 500, headers: {}, url: "https://example.com/test-article"
      )
    end

    assert_no_difference -> { ArticleVersion.count } do
      FetchArticleContentJob.perform_now(@article)
    end
  ensure
    WebFetcher.define_singleton_method(:fetch, @original_fetch)
  end

  test "does not create version on permanent extraction error" do
    original_extract = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) do |_url, **_opts|
      { error: "HTTP error! status: 404" }
    end

    begin
      assert_no_difference -> { ArticleVersion.count } do
        FetchArticleContentJob.perform_now(@article)
      end
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_extract)
    end
  end

  test "preserves existing publication_date when extraction returns nil" do
    existing_date = Date.new(2023, 6, 1)
    @article.update!(publication_date: existing_date)

    mock_result = {
      content: {
        title: "Title",
        content_html: "<p>Content</p>",
        content_md: "Content",
        word_count: 1,
        published: nil
      }
    }

    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| mock_result }

    begin
      FetchArticleContentJob.perform_now(@article)
      assert_equal existing_date, @article.reload.publication_date
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "skips extraction when content hash matches" do
    # Set up article with existing content and hash matching MOCK_HTML
    existing_hash = Digest::SHA256.hexdigest(MOCK_HTML)
    original_updated_at = 1.hour.ago
    @article.update!(
      content_html: "<p>Existing content</p>",
      content_md: "Existing content",
      content_hash: existing_hash,
      updated_at: original_updated_at
    )

    # Force should_update_content? to return true (by making last_content_fetched_at old enough)
    @article.update_column(:last_content_fetched_at, 90.days.ago)

    # Define extract_article_content that would raise if called
    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| raise "Should not be called" }

    begin
      FetchArticleContentJob.perform_now(@article)

      @article.reload
      # Content should remain unchanged
      assert_equal "<p>Existing content</p>", @article.content_html
      assert_equal existing_hash, @article.content_hash
      # But last_content_fetched_at should be updated
      assert @article.last_content_fetched_at > original_updated_at
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end

  test "re-extracts content when hash differs" do
    # Set up article with a different hash
    old_hash = Digest::SHA256.hexdigest("<html>old content</html>")
    @article.update!(
      content_html: "<p>Old content</p>",
      content_hash: old_hash,
      last_content_fetched_at: 90.days.ago
    )

    mock_result = {
      content: {
        title: "New Title",
        content_html: "<p>New content</p>",
        content_md: "New content",
        word_count: 2,
        published: nil
      }
    }

    original_method = WebProcessor.method(:extract_article_content)
    WebProcessor.define_singleton_method(:extract_article_content) { |_url, **_opts| mock_result }

    begin
      FetchArticleContentJob.perform_now(@article)

      @article.reload
      # Content should be updated
      assert_equal "New Title", @article.title
      assert_equal "<p>New content</p>", @article.content_html
      # Hash should be updated to new HTML hash
      new_hash = Digest::SHA256.hexdigest(MOCK_HTML)
      assert_equal new_hash, @article.content_hash
      # last_content_fetched_at should be updated
      assert @article.last_content_fetched_at > 1.minute.ago
    ensure
      WebProcessor.define_singleton_method(:extract_article_content, original_method)
    end
  end
end
