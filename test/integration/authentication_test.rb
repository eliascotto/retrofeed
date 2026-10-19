require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:test_user)
    @website = websites(:one)
    @article = articles(:one)
  end

  # Test that login routes are accessible without authentication
  test "login page is accessible without authentication" do
    get new_session_path
    assert_response :success
  end

  test "login POST is accessible without authentication" do
    login_as(@user)
    assert_response :redirect
  end

  # Health check should be publicly accessible without authentication
  test "health check is publicly accessible" do
    get rails_health_check_path
    assert_response :success
  end

  test "root requires authentication" do
    get root_path
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "sites index requires authentication" do
    get sites_path
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "site show requires authentication" do
    get site_path(@website)
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "article show requires authentication" do
    get article_path(@article)
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "mark article as read requires authentication" do
    post mark_read_user_article_path(@article)
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "random article requires authentication" do
    post random_article_path(@article)
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "next article requires authentication" do
    post next_article_path(@article)
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "settings show requires authentication" do
    get settings_path
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "logout requires authentication" do
    delete session_path(@user.id)
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  # Site refresh
  test "site refresh requires authentication" do
    post site_refresh_path(@website)
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "api article refresh requires authentication" do
    post refresh_api_article_path(@article)
    assert_redirected_to new_session_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  # Test that authenticated users can access routes
  test "authenticated user can access health check" do
    login_as(@user)
    get rails_health_check_path
    assert_response :success
  end

  test "authenticated user can access root" do
    login_as(@user)
    get root_path
    assert_response :success
  end

  test "authenticated user can access sites index" do
    login_as(@user)
    get sites_path
    assert_response :success
  end

  test "authenticated user can access settings" do
    login_as(@user)
    get settings_path
    assert_response :success
  end
end
