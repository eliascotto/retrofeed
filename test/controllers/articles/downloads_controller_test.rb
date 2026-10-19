require "test_helper"

class Articles::DownloadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:test_user)
    @article = articles(:one)
  end

  test "requires authentication for existing article" do
    post article_download_path(@article)
    assert_redirected_to new_session_path
  end

  test "returns 404 when article does not exist" do
    login_as(@user)
    post article_download_path(999999)
    assert_response :not_found
  end

  test "returns 403 when user is not subscribed to the article website" do
    login_as(@user)
    post article_download_path(articles(:two))
    assert_response :forbidden
  end

  test "returns 200 without enqueuing when article is already crawling" do
    login_as(@user)
    @article.update_columns(status: "crawling")

    assert_no_enqueued_jobs(only: FetchArticleContentJob) do
      post article_download_path(@article)
    end

    assert_response :success
    assert UserArticle.exists?(user: @user, article: @article)
  end

  test "returns 200, enqueues FetchArticleContentJob and sets status to crawling" do
    login_as(@user)

    assert_enqueued_with(job: FetchArticleContentJob) do
      post article_download_path(@article)
    end

    assert_response :success
    assert_equal "crawling", @article.reload.status
    assert UserArticle.exists?(user: @user, article: @article)
  end

  test "creates user_article record when none exists" do
    login_as(@user)
    # articles(:one) already has a UserArticle for test_user from fixtures —
    # use a freshly created article with no UserArticle
    article = Article.create!(website: websites(:one), title: "New", url: "https://example.com/new")
    stub_singleton(WebProcessor, :should_update_content?, false) do
      post article_download_path(article)
    end
    assert UserArticle.exists?(user: users(:test_user), article: article)
  end

  test "does not duplicate user_article on repeat download" do
    login_as(@user)

    stub_singleton(WebProcessor, :should_update_content?, false) do
      2.times { post article_download_path(articles(:one)) }
    end
    assert_equal 1, UserArticle.where(user: users(:test_user), article: articles(:one)).count
  end
end
