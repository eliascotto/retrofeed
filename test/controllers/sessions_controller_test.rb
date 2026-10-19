require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "should redirect to root path after successful login" do
    user = users(:test_user)
    login_as(user)
    assert_redirected_to root_path
    assert_equal "Logged in successfully", flash[:notice]
    assert_equal user.id, session[:user_id]
  end

  test "should redirect admin to root path after successful login" do
    admin = users(:admin)
    login_as(admin)
    assert_redirected_to root_path
    assert_equal "Logged in successfully", flash[:notice]
    assert_equal admin.id, session[:user_id]
  end

  test "should not redirect to home after failed login" do
    user = users(:test_user)
    login_as(user, password: "wrongpassword")
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_equal "Invalid email or password", flash[:alert]
  end

  test "should not redirect to home after login with wrong email" do
    user = users(:test_user)
    user.email = "nonexistent@example.com"
    login_as(user)
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    assert_equal "Invalid email or password", flash[:alert]
  end

  test "should allow access to login page when not authenticated" do
    get new_session_path
    assert_response :success
  end

  test "should logout and redirect to login" do
    user = users(:test_user)
    login_as(user)
    assert_equal user.id, session[:user_id]

    delete session_path(user.id)
    assert_redirected_to new_session_path
    assert_equal "Logged out successfully", flash[:notice]
    assert_nil session[:user_id]
  end

  test "should redirect unconfirmed user to confirmation page" do
    user = users(:unconfirmed_user)
    login_as(user)
    assert_redirected_to new_confirmation_path
    assert_equal "Please confirm your email address to continue", flash[:alert]
  end

  test "should set unconfirmed_user_id in session for unconfirmed user" do
    user = users(:unconfirmed_user)
    login_as(user)
    assert_equal user.id, session[:unconfirmed_user_id]
  end

  test "should not set user_id in session for unconfirmed user" do
    user = users(:unconfirmed_user)
    login_as(user)
    assert_nil session[:user_id]
  end

  test "should redirect to handle setup for user without handle" do
    user = users(:user_without_handle)
    login_as(user)
    assert_redirected_to new_handle_setup_path
    assert_match /Logged in successfully/, flash[:notice]
    assert_equal user.id, session[:user_id]
  end

  test "should redirect to root for user with handle" do
    user = users(:test_user)
    login_as(user)
    assert_redirected_to root_path
    assert_equal "Logged in successfully", flash[:notice]
  end
end
