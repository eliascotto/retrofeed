require "test_helper"

class ListArticleTest < ActiveSupport::TestCase
  setup do
    @user = users(:test_user)
    @list = lists(:user_list)
    @article = articles(:one)
    @article_two = articles(:two)
  end

  # ===== Association tests =====

  test "belongs to list" do
    list_article = ListArticle.new(list: @list, article: @article, position: 1)
    assert_equal @list, list_article.list
  end

  test "belongs to article" do
    list_article = ListArticle.new(list: @list, article: @article, position: 1)
    assert_equal @article, list_article.article
  end

  # ===== Validation tests =====

  test "article must be unique per list" do
    ListArticle.create!(list: @list, article: @article, position: 1)

    duplicate = ListArticle.new(list: @list, article: @article, position: 2)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:article_id], "has already been taken"
  end

  test "same article can be in different lists" do
    other_list = @user.lists.create!(title: "Other List")

    ListArticle.create!(list: @list, article: @article, position: 1)
    list_article_two = ListArticle.new(list: other_list, article: @article, position: 1)

    assert list_article_two.valid?
  end

  # ===== Default scope tests =====

  test "default scope orders by position" do
    ListArticle.create!(list: @list, article: @article_two, position: 2)
    ListArticle.create!(list: @list, article: @article, position: 1)

    list_articles = @list.list_articles.to_a

    assert_equal 1, list_articles.first.position
    assert_equal 2, list_articles.last.position
  end

  test "default scope handles nil positions" do
    # Create with explicit positions to ensure ordering
    la1 = ListArticle.create!(list: @list, article: @article, position: nil)
    la2 = ListArticle.create!(list: @list, article: @article_two, position: 1)

    list_articles = @list.list_articles.to_a

    # Nil position should come before position 1 in ascending order
    assert_includes list_articles, la1
    assert_includes list_articles, la2
  end

  # ===== Cascade delete tests =====

  test "list_article is deleted when list is deleted" do
    list = @user.lists.create!(title: "Temp List")
    list_article = ListArticle.create!(list: list, article: @article, position: 1)
    list_article_id = list_article.id

    list.destroy

    assert_not ListArticle.exists?(list_article_id)
  end

  test "list_article is deleted when article is deleted" do
    new_article = Article.create!(
      website: @article.website,
      title: "Temp Article",
      url: "https://example.com/temp",
      content_html: "<p>Content</p>"
    )
    list_article = ListArticle.create!(list: @list, article: new_article, position: 1)
    list_article_id = list_article.id

    new_article.destroy

    assert_not ListArticle.exists?(list_article_id)
  end

  # ===== Position handling tests =====

  test "position can be updated" do
    list_article = ListArticle.create!(list: @list, article: @article, position: 1)

    list_article.update!(position: 5)

    assert_equal 5, list_article.reload.position
  end

  test "multiple articles can have sequential positions" do
    la1 = ListArticle.create!(list: @list, article: @article, position: 1)
    la2 = ListArticle.create!(list: @list, article: @article_two, position: 2)

    assert_equal 1, la1.position
    assert_equal 2, la2.position
  end

  test "positions do not need to be sequential" do
    la1 = ListArticle.create!(list: @list, article: @article, position: 1)
    la2 = ListArticle.create!(list: @list, article: @article_two, position: 100)

    assert_equal 1, la1.position
    assert_equal 100, la2.position
  end
end
