require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:test_user)
    @website = websites(:one)
    # Ensure user is subscribed to website one
    Subscription.find_or_create_by(user: @user, website: @website)
  end

  test "should redirect to login when not authenticated" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "should render home page when authenticated" do
    login_as(@user)
    get root_path
    assert_response :success
  end

  test "root_path helper generates correct URL" do
    assert_equal "/", root_path
  end

  test "should default to recent tab" do
    login_as(@user)
    get root_path
    assert_response :success
    assert_select "a[href='#{root_path(tab: 'recent')}'].border-primary"
  end

  test "should switch to reading tab" do
    login_as(@user)
    get root_path(tab: "reading")
    assert_response :success
    assert_select "a[href='#{root_path(tab: 'reading')}'].border-primary"
  end

  test "should save tab preference when switching tabs" do
    login_as(@user)

    # Switch to reading tab
    get root_path(tab: "reading")
    assert_response :success

    # Reload user and check preference was saved
    @user.reload
    assert_equal "reading", @user.home_tab_preference
  end

  test "should remember tab preference across visits" do
    @user.update_home_tab_preference("reading")

    login_as(@user)
    get root_path
    assert_response :success
    # Should default to reading tab based on saved preference
    assert_select "a[href='#{root_path(tab: 'reading')}'].border-primary"
  end

  test "recent tab shows unread articles" do
    # Create a new unread article
    article = Article.create!(
      website: @website,
      title: "Unread Article",
      url: "https://example.com/unread",
      content_html: "Content"
    )

    login_as(@user)
    get root_path(tab: "recent")
    assert_response :success
    assert_select ".text-sm.font-medium", text: "Unread Article"
  end

  test "reading tab shows opened but unfinished articles" do
    # Create an article and open it (create reading state without read_at)
    article = Article.create!(
      website: @website,
      title: "In Progress Article",
      url: "https://example.com/in-progress",
      content_html: "Content"
    )
    UserArticle.create!(user: @user, article: article, read_at: nil)

    login_as(@user)
    get root_path(tab: "reading")
    assert_response :success
    assert_select ".text-sm.font-medium", text: "In Progress Article"
  end

  test "reading tab excludes finished articles" do
    # Article one has reading state with read_at set
    login_as(@user)
    get root_path(tab: "reading")
    assert_response :success
    # Article one should not appear since it's finished
    assert_select ".text-sm.font-medium", text: "First Article", count: 0
  end

  test "reading tab orders by last opened" do
    # Create two articles with reading states
    article1 = Article.create!(
      website: @website,
      title: "Opened First",
      url: "https://example.com/first",
      content_html: "Content"
    )
    article2 = Article.create!(
      website: @website,
      title: "Opened Second",
      url: "https://example.com/second",
      content_html: "Content"
    )

    # Create reading states with different updated_at times
    UserArticle.create!(user: @user, article: article1, read_at: nil, updated_at: 1.hour.ago)
    UserArticle.create!(user: @user, article: article2, read_at: nil, updated_at: Time.current)

    login_as(@user)
    get root_path(tab: "reading")
    assert_response :success

    # Article2 should appear first (most recently opened)
    response_body = response.body
    assert response_body.index("Opened Second") < response_body.index("Opened First"),
           "Most recently opened article should appear first"
  end

  test "pagination works on recent tab" do
    # Create more than 20 articles to test pagination
    25.times do |i|
      Article.create!(
        website: @website,
        title: "Article #{i}",
        url: "https://example.com/article-#{i}",
        content_html: "Content"
      )
    end

    login_as(@user)
    get root_path(tab: "recent", page: 1)
    assert_response :success

    # Should show pagination controls
    assert_select "input[name='page']"
    assert_select "select[name='per_page']"
  end
end
