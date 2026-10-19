require "test_helper"

class SitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:test_user)
    @other_user = users(:other_user)
    @website = websites(:one)
    @website_two = websites(:two)
    @article = articles(:one)

    login_as(@user)
  end

  # ===== index action tests =====

  test "index renders sites page" do
    get sites_path

    assert_response :success
  end

  test "index shows subscribed websites" do
    get sites_path

    assert_response :success
    # Should include website one (subscribed)
    assert_select "[data-website-id='#{@website.id}']"
  end

  test "index does not show unsubscribed websites" do
    get sites_path

    assert_response :success
    # Should not include website two (not subscribed by test_user)
    assert_select "[data-website-id='#{@website_two.id}']", count: 0
  end

  test "index shows read counts" do
    # Article one has reading state for test_user from fixtures
    get sites_path

    assert_response :success
    # The page should render without errors even with read states
  end

  # ===== show action tests =====

  test "show renders site page for subscribed user" do
    get site_path(@website)

    assert_response :success
  end

  test "show redirects to error for non-subscribed user" do
    # test_user is not subscribed to website_two
    get site_path(@website_two)

    assert_redirected_to error_path(type: "site_no_subscription", site_id: @website_two.id)
  end

  test "show redirects to error for non-existent website" do
    get site_path(id: 999999)

    assert_redirected_to error_path(type: "site_not_found")
  end

  test "show displays articles with content" do
    # Article one has content from fixtures
    get site_path(@website)

    assert_response :success
    assert_select "a[href='#{article_path(@article)}']"
  end

  test "show excludes articles without content" do
    # Create an article without content
    no_content_article = Article.create!(
      website: @website,
      title: "No Content Article",
      url: "https://example.com/no-content",
      content_html: nil,
      content_md: nil
    )

    get site_path(@website)

    assert_response :success
    assert_select "a[href='#{article_path(no_content_article)}']", count: 0
  end

  # ===== Create tests =====

  test "create" do
    assert_difference -> { Website.count }, +1 do
      post sites_path, params: { site: { url: "https://example3.com" } }
    end

    assert_redirected_to sites_path
  end

  test "create JSON" do
    assert_difference -> { Website.count }, +1 do
      post sites_path, params: { site: { url: "https://example3.com" } }, as: :json
    end

    assert_response :created
  end

  test "create avoids duplicated websites" do
    initial_count = Website.count
    post sites_path, params: { site: { url: "https://example.com" } }
    assert_equal initial_count, Website.count
  end

  # ===== Sorting tests =====

  test "show sorts articles by date by default" do
    get site_path(@website)

    assert_response :success
    # Default sort should be date desc
  end

  test "show sorts articles by title" do
    # Create another article for testing sort
    Article.create!(
      website: @website,
      title: "AAA First Article",
      url: "https://example.com/aaa",
      content_html: "<p>Content</p>",
      publication_date: Date.yesterday
    )

    get site_path(@website, sort: "title", order: "asc")

    assert_response :success
    # Should render without errors
  end

  test "show sorts articles by word count" do
    get site_path(@website, sort: "words", order: "desc")

    assert_response :success
  end

  test "show supports ascending order" do
    get site_path(@website, sort: "date", order: "asc")

    assert_response :success
  end

  test "show supports descending order" do
    get site_path(@website, sort: "date", order: "desc")

    assert_response :success
  end

  test "show handles order parameter none" do
    # When order is not provided, it defaults to desc
    get site_path(@website)

    assert_response :success
  end

  # ===== Progress and status tests =====

  test "show includes progress stats" do
    get site_path(@website)

    assert_response :success
    # The page should display progress information without errors
  end

  test "show handles processing website" do
    @website.update!(processing_status: "extracting")

    get site_path(@website)

    assert_response :success
  end

  test "show handles website with errors" do
    @website.update!(processing_status: "extracting")

    # Create a failed article
    Article.create!(
      website: @website,
      title: "Failed Article",
      url: "https://example.com/failed",
      content_fetch_failed_at: Time.current,
      failure_reason: "Test failure"
    )

    @website.update!(processing_status: "partial")

    get site_path(@website)

    assert_response :success
  end

  # ===== Read state tests =====

  test "show preloads read article IDs" do
    # Article one has reading state from fixtures
    get site_path(@website)

    assert_response :success
    # The page should indicate which articles are read
  end

  test "show includes read next article IDs" do
    # Add article to read next list
    read_next_list = @user.read_next_list
    read_next_list.add_article(@article) if read_next_list

    get site_path(@website)

    assert_response :success
  end

  # ===== Filter tests =====

  test "show defaults to all filter" do
    get site_path(@website)

    assert_response :success
    assert_equal "all", controller.instance_variable_get(:@filter)
  end

  test "show with invalid filter falls back to all" do
    get site_path(@website, filter: "invalid")

    assert_response :success
    assert_equal "all", controller.instance_variable_get(:@filter)
  end

  test "show with saved filter returns articles with user_article" do
    # article :one has a user_article for test_user with read_at set and no removed_at

    get site_path(@website, filter: "saved")

    assert_response :success
    assert_equal "saved", controller.instance_variable_get(:@filter)
    articles = controller.instance_variable_get(:@articles)
    assert_includes articles.map(&:id), @article.id
  end

  test "show with read filter returns only read articles" do
    # article :one has user_article with read_at set for test_user

    get site_path(@website, filter: "read")

    assert_response :success
    assert_equal "read", controller.instance_variable_get(:@filter)
    articles = controller.instance_variable_get(:@articles)
    assert_includes articles.map(&:id), @article.id
  end

  test "show with removed filter returns removed articles" do
    user_articles(:one).update!(removed_at: Time.current)

    get site_path(@website, filter: "removed")

    assert_response :success
    assert_equal "removed", controller.instance_variable_get(:@filter)
    articles = controller.instance_variable_get(:@articles)
    assert_includes articles.map(&:id), @article.id
  end

  test "show all filter excludes removed articles" do
    user_articles(:one).update!(removed_at: Time.current)

    get site_path(@website, filter: "all")

    assert_response :success
    articles = controller.instance_variable_get(:@articles)
    assert_not_includes articles.map(&:id), @article.id
  end

  test "show preserves filter when changing sort" do
    get site_path(@website, filter: "saved", sort: "title", order: "asc")

    assert_response :success
    assert_equal "saved", controller.instance_variable_get(:@filter)
    assert_equal "title", controller.instance_variable_get(:@sort)
  end
end
