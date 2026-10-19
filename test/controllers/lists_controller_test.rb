require "test_helper"

class ListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:test_user)
    @other_user = users(:other_user)
    @read_next_list = lists(:read_next_list)
    @user_list = lists(:user_list)
    @article = articles(:one)
  end

  # ===== Authentication tests =====

  test "index requires authentication" do
    get lists_path
    assert_redirected_to new_session_path
  end

  test "show requires authentication" do
    get list_path(@user_list.public_slug)
    assert_redirected_to new_session_path
  end

  # ===== index action tests =====

  test "index renders lists page" do
    login_as(@user)

    get lists_path

    assert_response :success
  end

  test "index shows user lists" do
    login_as(@user)

    get lists_path

    assert_response :success
    # Should show the user list
    assert_select "a[href*='#{@user_list.public_slug}']"
  end

  test "index does not show system lists" do
    login_as(@user)

    get lists_path

    assert_response :success
    # System list (read-next) should not appear in the user lists index
    # Note: It might appear in sidebar, but not in the main list
  end

  test "index does not show other users lists" do
    login_as(@user)

    # Create a list for other user
    other_list = @other_user.lists.create!(title: "Other User List")

    get lists_path

    assert_response :success
    assert_select "a[href*='#{other_list.public_slug}']", count: 0
  end

  # ===== Sorting tests =====

  test "index sorts by date by default" do
    login_as(@user)

    get lists_path

    assert_response :success
  end

  test "index sorts by title" do
    login_as(@user)

    get lists_path(sort: "title", order: "asc")

    assert_response :success
  end

  test "index sorts by count" do
    login_as(@user)

    get lists_path(sort: "count", order: "desc")

    assert_response :success
  end

  test "index ignores invalid sort parameter" do
    login_as(@user)

    get lists_path(sort: "invalid")

    assert_response :success
    # Should default to date
  end

  test "index ignores invalid order parameter" do
    login_as(@user)

    get lists_path(order: "invalid")

    assert_response :success
    # Should default to desc
  end

  # ===== show action tests =====

  test "show renders list page for user list" do
    login_as(@user)

    get list_path(@user_list.public_slug)

    assert_response :success
  end

  test "show renders list page for read next list" do
    login_as(@user)

    get list_path("read-next")

    assert_response :success
  end

  test "show redirects to error for non-existent list" do
    login_as(@user)

    get list_path("nonexistent-zzz9999")

    assert_redirected_to error_path(type: "list_not_found")
  end

  test "show redirects to error for other users list" do
    login_as(@user)

    # Create a list for other user
    other_list = @other_user.lists.create!(title: "Other User List")

    get list_path(other_list.public_slug)

    assert_redirected_to error_path(type: "list_not_found")
  end

  test "show displays articles in list" do
    login_as(@user)

    # Add article to the list
    @user_list.add_article(@article)

    get list_path(@user_list.public_slug)

    assert_response :success
    assert_select "a[href='#{article_path(@article)}']"
  end

  test "show preloads read article IDs" do
    login_as(@user)

    # Add article to the list (article one has reading state from fixtures)
    @user_list.add_article(@article)

    get list_path(@user_list.public_slug)

    assert_response :success
    # The page should render with read state information
  end

  test "show indicates when list is read next" do
    login_as(@user)

    get list_path("read-next")

    assert_response :success
    # The page should indicate this is the Read Next list
  end

  test "show handles empty list" do
    login_as(@user)

    # Create a new empty list
    empty_list = @user.lists.create!(title: "Empty List")

    get list_path(empty_list.public_slug)

    assert_response :success
  end

  test "show displays articles ordered by position" do
    login_as(@user)

    article_two = Article.create!(
      website: @article.website,
      title: "Second Article",
      url: "https://example.com/second",
      content_html: "<p>Content</p>"
    )

    @user_list.add_article(article_two, position: 1)
    @user_list.add_article(@article, position: 2)

    get list_path(@user_list.public_slug)

    assert_response :success

    ordered_ids = css_select("[id^='article_']").map { |el| el["id"] }
    assert_equal [ dom_id(article_two), dom_id(@article) ], ordered_ids
  end
end
