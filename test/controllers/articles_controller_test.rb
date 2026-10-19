require "test_helper"

class ArticlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:test_user)
    @other_user = users(:other_user)
    @website = websites(:one)
    @website_two = websites(:two)
    @article = articles(:one)
    @article_two = articles(:two)

    # Ensure test_user is subscribed to website one (from fixtures)
    # and other_user is subscribed to website two
  end

  # ===== Authentication tests =====

  test "show requires authentication" do
    get article_path(@article)
    assert_redirected_to new_session_path
  end

  test "mark_read requires authentication" do
    post mark_read_user_article_path(@article)
    assert_redirected_to new_session_path
  end

  test "random requires authentication" do
    post random_article_path(@article)
    assert_redirected_to new_session_path
  end

  test "next_article requires authentication" do
    post next_article_path(@article)
    assert_redirected_to new_session_path
  end

  # ===== show action tests =====

  test "show renders article page for subscribed user" do
    login_as(@user)

    get article_path(@article)

    assert_response :success
    assert_select "h1", text: @article.title
  end

  test "show redirects to error for non-subscribed user" do
    login_as(@user)

    # test_user is not subscribed to website_two
    get article_path(@article_two)

    assert_redirected_to error_path(type: "article_no_subscription", site_id: @website_two.id)
  end

  test "show redirects to error for non-existent article" do
    login_as(@user)

    get article_path(id: 999999)

    assert_redirected_to error_path(type: "article_not_found")
  end

  # ===== mark_read action tests =====

  test "mark_read creates reading state if none exists" do
    login_as(@user)

    # Use a new article without existing reading state
    new_article = Article.create!(
      website: @website,
      title: "New Article",
      url: "https://example.com/new-article",
      content_html: "<p>Content</p>"
    )

    assert_difference "UserArticle.count", 1 do
      post mark_read_user_article_path(new_article)
    end

    user_article = UserArticle.find_by(user: @user, article: new_article)
    assert_not_nil user_article.read_at
  end

  test "mark_read updates existing reading state" do
    login_as(@user)

    # Use a new article without existing reading state
    new_article = Article.create!(
      website: @website,
      title: "In Progress Article",
      url: "https://example.com/in-progress",
      content_html: "<p>Content</p>"
    )

    # Create an in-progress reading state (read_at is nil)
    UserArticle.create!(user: @user, article: new_article, read_at: nil)

    assert_no_difference "UserArticle.count" do
      post mark_read_user_article_path(new_article)
    end

    user_article = UserArticle.find_by(user: @user, article: new_article)
    assert_not_nil user_article.read_at
  end

  test "mark_read does not update already read article" do
    login_as(@user)

    # Use a new article without existing reading state
    new_article = Article.create!(
      website: @website,
      title: "Already Read Article",
      url: "https://example.com/already-read",
      content_html: "<p>Content</p>"
    )

    original_read_at = 1.hour.ago
    UserArticle.create!(user: @user, article: new_article, read_at: original_read_at)

    post mark_read_user_article_path(new_article)

    user_article = UserArticle.find_by(user: @user, article: new_article)
    # read_at should not change since it was already set
    # Use a larger delta since timestamps may have microsecond differences
    assert_in_delta original_read_at.to_i, user_article.read_at.to_i, 1
  end

  test "mark_read redirects to site page" do
    login_as(@user)

    post mark_read_user_article_path(@article)

    assert_response :ok
  end

  # ===== random action tests =====

  test "random marks current article as read" do
    login_as(@user)

    post random_article_path(@article)

    user_article = UserArticle.find_by(user: @user, article: @article)
    assert_not_nil user_article
    assert_not_nil user_article.read_at
  end

  test "random redirects to another unread article" do
    login_as(@user)

    # Create another unread article for the same user's subscription
    unread_article = Article.create!(
      website: @website,
      title: "Unread Article",
      url: "https://example.com/unread",
      content_html: "<p>Content</p>"
    )

    post random_article_path(@article)

    # Should redirect to the unread article (only one available)
    assert_redirected_to article_path(unread_article)
  end

  test "random redirects to site with notice when no more unread articles" do
    login_as(@user)

    # The fixture already marks article :one as read for test_user
    post random_article_path(@article)

    assert_redirected_to site_path(@website)
    assert_equal "No more unread articles", flash[:notice]
  end

  # ===== next_article action tests =====

  test "next_article marks current article as read" do
    login_as(@user)

    # Use a new article without existing reading state
    new_article = Article.create!(
      website: @website,
      title: "Current Article",
      url: "https://example.com/current",
      content_html: "<p>Content</p>"
    )

    post next_article_path(new_article)

    user_article = UserArticle.find_by(user: @user, article: new_article)
    assert_not_nil user_article
    assert_not_nil user_article.read_at
  end

  test "next_article redirects to next unread article from same site" do
    login_as(@user)

    # Create current article
    current_article = Article.create!(
      website: @website,
      title: "Current Article",
      url: "https://example.com/current-article",
      content_html: "<p>Content</p>"
    )

    # Create another unread article for the same website
    unread_article = Article.create!(
      website: @website,
      title: "Next Unread",
      url: "https://example.com/next-unread",
      content_html: "<p>Content</p>"
    )

    post next_article_path(current_article)

    assert_redirected_to article_path(unread_article)
  end

  test "next_article does not redirect to article from different site" do
    login_as(@user)

    # Create current article
    current_article = Article.create!(
      website: @website,
      title: "Current Article",
      url: "https://example.com/current-for-diff",
      content_html: "<p>Content</p>"
    )

    # Subscribe user to website_two as well
    Subscription.create!(user: @user, website: @website_two)

    # Create an unread article for website_two
    Article.create!(
      website: @website_two,
      title: "Different Site Article",
      url: "https://example2.com/different",
      content_html: "<p>Content</p>"
    )

    post next_article_path(current_article)

    # Should redirect to site page since there's no next article from same site
    assert_redirected_to site_path(@website)
    assert_equal "No more unread articles from this site", flash[:notice]
  end

  test "next_article redirects to site with notice when no more unread articles from site" do
    login_as(@user)

    # Create current article (the only one)
    current_article = Article.create!(
      website: @website,
      title: "Only Article",
      url: "https://example.com/only-article",
      content_html: "<p>Content</p>"
    )

    post next_article_path(current_article)

    assert_redirected_to site_path(@website)
    assert_equal "No more unread articles from this site", flash[:notice]
  end

  # ===== Edge cases =====

  test "mark_read handles non-existent article" do
    login_as(@user)

    post mark_read_user_article_path(article_id: 999999)

    assert_response :not_found
  end

  test "random handles non-existent article" do
    login_as(@user)

    post random_article_path(id: 999999)

    assert_redirected_to error_path(type: "article_not_found")
  end

  test "next_article handles non-existent article" do
    login_as(@user)

    post next_article_path(id: 999999)

    assert_redirected_to error_path(type: "article_not_found")
  end
end
