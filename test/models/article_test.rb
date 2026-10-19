require "test_helper"

class ArticleTest < ActiveSupport::TestCase
  setup do
    @website = websites(:one)
  end

  # ===== content_text method tests =====

  test "content_text returns empty string when no content" do
    article = Article.new(website: @website)
    assert_equal "", article.content_text
  end

  test "content_text returns plain text from HTML" do
    article = Article.new(website: @website, content_html: "<p>This is a <strong>test</strong> article</p>")
    assert_equal "This is a test article", article.content_text
  end

  test "content_text returns plain text from markdown" do
    article = Article.new(website: @website, content_md: "# This is a test article\n\nWith **bold** text")
    # Markdown is converted to HTML then stripped, so we get plain text
    text = article.content_text
    assert_includes text, "This is a test article"
    assert_includes text, "bold"
    assert_not_includes text, "<"
    assert_not_includes text, ">"
  end

  test "content_text prefers markdown over HTML when both present" do
    article = Article.new(
      website: @website,
      content_html: "<p>HTML content</p>",
      content_md: "# Markdown content"
    )
    text = article.content_text
    assert_includes text, "Markdown content"
    assert_not_includes text, "HTML content"
  end

  test "content_text handles empty HTML string" do
    article = Article.new(website: @website, content_html: "")
    assert_equal "", article.content_text
  end

  test "content_text handles empty markdown string" do
    article = Article.new(website: @website, content_md: "")
    assert_equal "", article.content_text
  end

  # ===== with_content scope tests =====

  test "with_content includes article with content_html only" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_html: "<p>Content</p>"
    )
    assert_includes Article.with_content, article
  end

  test "with_content includes article with content_md only" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_md: "# Content"
    )
    assert_includes Article.with_content, article
  end

  test "with_content includes article with both content_html and content_md" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_html: "<p>HTML</p>",
      content_md: "# Markdown"
    )
    assert_includes Article.with_content, article
  end

  test "with_content excludes article with both content_html and content_md as nil" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_html: nil,
      content_md: nil
    )
    assert_not_includes Article.with_content, article
  end

  test "with_content excludes article with both content_html and content_md as empty strings" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_html: "",
      content_md: ""
    )
    assert_not_includes Article.with_content, article
  end

  test "with_content includes article when content_html is nil but content_md is present" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_html: nil,
      content_md: "# Content"
    )
    assert_includes Article.with_content, article
  end

  test "with_content includes article when content_html is empty but content_md is present" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_html: "",
      content_md: "# Content"
    )
    assert_includes Article.with_content, article
  end

  test "with_content includes article when content_md is nil but content_html is present" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_html: "<p>Content</p>",
      content_md: nil
    )
    assert_includes Article.with_content, article
  end

  test "with_content includes article when content_md is empty but content_html is present" do
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/test",
      content_html: "<p>Content</p>",
      content_md: ""
    )
    assert_includes Article.with_content, article
  end

  test "with_content scope can be chained with other scopes" do
    article_with_content = Article.create!(
      website: @website,
      title: "With Content",
      url: "https://example.com/with",
      content_html: "<p>Content</p>"
    )
    article_without = Article.create!(
      website: @website,
      title: "Without Content",
      url: "https://example.com/without",
      content_html: nil,
      content_md: nil
    )

    results = Article.where(website: @website).with_content
    assert_includes results, article_with_content
    assert_not_includes results, article_without
  end

  # ===== read_by? method tests =====

  test "read_by? returns true when user has read the article" do
    user = users(:test_user)
    article = Article.create!(
      website: @website,
      title: "Read Article",
      url: "https://example.com/read-test",
      content_html: "<p>Content</p>"
    )
    UserArticle.create!(user: user, article: article, read_at: Time.current)

    assert article.read_by?(user)
  end

  test "read_by? returns false when user has not read the article" do
    user = users(:test_user)
    article = Article.create!(
      website: @website,
      title: "Unread Article",
      url: "https://example.com/unread-test",
      content_html: "<p>Content</p>"
    )

    assert_not article.read_by?(user)
  end

  test "read_by? returns false when user has started but not finished the article" do
    user = users(:test_user)
    article = Article.create!(
      website: @website,
      title: "In Progress Article",
      url: "https://example.com/in-progress-test",
      content_html: "<p>Content</p>"
    )
    # Reading state exists but read_at is nil (in progress)
    UserArticle.create!(user: user, article: article, read_at: nil)

    assert_not article.read_by?(user)
  end

  test "read_by? returns correct result for different users" do
    user1 = users(:test_user)
    user2 = users(:other_user)
    article = Article.create!(
      website: @website,
      title: "Mixed Read Article",
      url: "https://example.com/mixed-test",
      content_html: "<p>Content</p>"
    )

    # User 1 has read it, user 2 has not
    UserArticle.create!(user: user1, article: article, read_at: Time.current)

    assert article.read_by?(user1)
    assert_not article.read_by?(user2)
  end

  # ===== Association cascade delete tests =====

  test "deleting article destroys associated reading states" do
    user = users(:test_user)
    article = Article.create!(
      website: @website,
      title: "Article with State",
      url: "https://example.com/with-state",
      content_html: "<p>Content</p>"
    )
    user_article = UserArticle.create!(user: user, article: article, read_at: Time.current)
    user_article_id = user_article.id

    article.destroy

    assert_not UserArticle.exists?(user_article_id)
  end

  test "deleting article destroys associated list_articles" do
    user = users(:test_user)
    list = lists(:user_list)
    article = Article.create!(
      website: @website,
      title: "Article in List",
      url: "https://example.com/in-list",
      content_html: "<p>Content</p>"
    )
    list_article = ListArticle.create!(list: list, article: article, position: 1)
    list_article_id = list_article.id

    article.destroy

    assert_not ListArticle.exists?(list_article_id)
  end

  test "deleting article destroys associated article_tags" do
    user = users(:test_user)
    tag = Tag.create!(user: user, name: "Test Tag")
    article = Article.create!(
      website: @website,
      title: "Tagged Article",
      url: "https://example.com/tagged",
      content_html: "<p>Content</p>"
    )
    article_tag = ArticleTag.create!(article: article, tag: tag)
    article_tag_id = article_tag.id

    article.destroy

    assert_not ArticleTag.exists?(article_tag_id)
  end
end
