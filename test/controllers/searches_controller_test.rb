require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:test_user)
    @website = websites(:one)
    @article = articles(:one)

    # Ensure user is subscribed to website
    Subscription.find_or_create_by(user: @user, website: @website)

    # Login
    login_as(@user)
  end

  test "should redirect to login when not authenticated" do
    delete session_path(@user.id)
    get search_path
    assert_redirected_to new_session_path
  end

  test "should render search page when authenticated" do
    get search_path
    assert_response :success
    assert_select "input[name='q']"
  end

  test "should show empty state when no query" do
    get search_path
    assert_response :success
    assert_select "p", text: /Start typing to search/
  end

  test "should search articles by title" do
    @article.update(title: "Rails Tutorial", content_html: "Some content")

    get search_path, params: { q: "Rails" }
    assert_response :success
    assert_select ".text-sm.font-medium", text: /Rails Tutorial/
  end

  test "should search articles by content" do
    @article.update(title: "Test Article", content_html: "This is about Rails development")

    get search_path, params: { q: "Rails" }
    assert_response :success
    assert_select ".text-sm.font-medium", text: /Test Article/
  end

  test "should search sites by name" do
    @website.update(name: "Rails Blog")

    get search_path, params: { q: "Rails", tab: "sites" }
    assert_response :success
    assert_select ".text-sm.font-medium", text: /Rails Blog/
  end

  test "should search sites by domain" do
    @website.update(name: "My Blog", domain: "rails.example.com")

    get search_path, params: { q: "rails", tab: "sites" }
    assert_response :success
    assert_select ".text-sm.font-medium", text: /My Blog/
  end

  test "should show tabs only when sites are available" do
    @article.update(title: "Test", content_html: "Content")
    @website.update(name: "Test Site")

    # Search that returns both articles and sites
    get search_path, params: { q: "Test" }
    assert_response :success
    assert_select "button[data-tab='articles']"
    assert_select "button[data-tab='sites']"
  end

  test "should not show tabs when only articles are available" do
    @article.update(title: "Test Article", content_html: "Content")
    @website.update(name: "Different Site")

    # Search that only returns articles
    get search_path, params: { q: "Article" }
    assert_response :success
    assert_select "button[data-tab='sites']", count: 0
  end

  test "should default to articles tab" do
    @article.update(title: "Test", content_html: "Content")
    @website.update(name: "Test Site")

    get search_path, params: { q: "Test" }
    assert_response :success
    assert_select "button[data-tab='articles'].border-primary"
  end

  test "should switch to sites tab" do
    @article.update(title: "Test", content_html: "Content")
    @website.update(name: "Test Site")

    get search_path, params: { q: "Test", tab: "sites" }
    assert_response :success
    assert_select "button[data-tab='sites'].border-primary"
  end

  test "should only show articles from subscribed websites" do
    other_website = websites(:two)
    other_article = Article.create!(
      website: other_website,
      title: "Other Article",
      url: "https://example.com/other",
      content_html: "Content"
    )

    get search_path, params: { q: "Article" }
    assert_response :success

    # Should not show article from unsubscribed website
    assert_select ".text-sm.font-medium", text: "Other Article", count: 0
  end

  test "should only show sites user is subscribed to" do
    other_website = websites(:two)
    other_website.update(name: "Other Site")

    get search_path, params: { q: "Site", tab: "sites" }
    assert_response :success

    # Should not show site user is not subscribed to
    assert_select ".text-sm.font-medium", text: "Other Site", count: 0
  end

  test "should handle special characters in search query" do
    @article.update(title: "Test % Article", content_html: "Content")

    get search_path, params: { q: "Test %" }
    assert_response :success
    # Should not raise error
  end

  test "should be case insensitive" do
    @article.update(title: "Rails Tutorial", content_html: "Content")

    get search_path, params: { q: "rails" }
    assert_response :success
    assert_select ".text-sm.font-medium", text: /Rails Tutorial/
  end

  test "paginates articles" do
    25.times do |i|
      Article.create!(
        website: @website,
        title: "Paginated Article #{i}",
        url: "https://example.com/#{i}",
        content_html: "Content #{i}"
      )
    end

    get search_path, params: { q: "Paginated", page: 1 }
    assert_response :success
    assert_select ".space-y-2 a .text-sm.font-medium", count: 20

    get search_path, params: { q: "Paginated", page: 2 }
    assert_response :success
    assert_select ".space-y-2 a .text-sm.font-medium", count: 5
    # Articles are ordered by created_at:desc, so article 24 (created last) is first
    # and article 0 (created first) is last. Article 24 should be on page 1, not page 2.
    assert_select ".space-y-2 a .text-sm.font-medium", text: /Paginated Article 24/, count: 0
  end

  test "paginates sites" do
    25.times do |i|
      website = Website.create!(
        name: "Paginated Site #{i}",
        domain: "paginated#{i}.example.com"
      )
      Subscription.create!(user: @user, website: website)
    end

    get search_path, params: { q: "Paginated", tab: "sites", page: 1 }
    assert_response :success
    assert_select ".space-y-2 a .text-sm.font-medium", count: 20

    get search_path, params: { q: "Paginated", tab: "sites", page: 2 }
    assert_response :success
    assert_select ".space-y-2 a .text-sm.font-medium", count: 5
    assert_select ".space-y-2 a .text-sm.font-medium", text: /Paginated Site 0/, count: 0
  end

  test "pagination links preserve query and tab" do
    25.times do |i|
      Article.create!(
        website: @website,
        title: "Paginated Article #{i}",
        url: "https://example.com/#{i}",
        content_html: "Content #{i}"
      )
    end

    get search_path, params: { q: "Paginated", tab: "articles", page: 2 }
    assert_response :success
    assert_select "a[href=?]", search_path(q: "Paginated", tab: "articles", per_page: 20, page: 1)
    assert_select "a[href=?]", search_path(q: "Paginated", tab: "articles", per_page: 20, page: 3), count: 0
  end

  test "handles empty pages gracefully" do
    get search_path, params: { q: "Nonexistent", page: 3 }
    assert_response :success
    assert_select ".space-y-2 a .text-sm.font-medium", count: 0
  end
end
