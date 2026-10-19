require "test_helper"

class ArticleVersionTest < ActiveSupport::TestCase
  setup do
    @article = articles(:one)
  end

  test "is valid with article, version, and content_hash" do
    version = ArticleVersion.new(
      article: @article,
      version: 1,
      content_hash: "abc123"
    )
    assert version.valid?
  end

  test "requires version" do
    version = ArticleVersion.new(article: @article, content_hash: "abc123")
    assert_not version.valid?
    assert_includes version.errors[:version], "can't be blank"
  end

  test "requires content_hash" do
    version = ArticleVersion.new(article: @article, version: 1)
    assert_not version.valid?
    assert_includes version.errors[:content_hash], "can't be blank"
  end

  test "requires article" do
    version = ArticleVersion.new(version: 1, content_hash: "abc123")
    assert_not version.valid?
    assert_includes version.errors[:article], "must exist"
  end

  test "version is unique scoped to article" do
    ArticleVersion.create!(article: @article, version: 1, content_hash: "h1")

    duplicate = ArticleVersion.new(article: @article, version: 1, content_hash: "h2")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version], "has already been taken"
  end

  test "same version number is valid across different articles" do
    other_article = articles(:two)
    ArticleVersion.create!(article: @article, version: 1, content_hash: "h1")

    same_version_other_article = ArticleVersion.new(
      article: other_article,
      version: 1,
      content_hash: "h2"
    )
    assert same_version_other_article.valid?
  end

  test "latest_first scope orders by version descending" do
    v1 = ArticleVersion.create!(article: @article, version: 1, content_hash: "h1")
    v3 = ArticleVersion.create!(article: @article, version: 3, content_hash: "h3")
    v2 = ArticleVersion.create!(article: @article, version: 2, content_hash: "h2")

    assert_equal [ v3, v2, v1 ], @article.article_versions.latest_first.to_a
  end

  test "deleting an article destroys its versions" do
    article = Article.create!(
      website: websites(:one),
      url: "https://example.com/disposable",
      title: "Disposable"
    )
    article.article_versions.create!(version: 1, content_hash: "h1")
    article.article_versions.create!(version: 2, content_hash: "h2")

    assert_difference -> { ArticleVersion.count }, -2 do
      article.destroy
    end
  end
end
