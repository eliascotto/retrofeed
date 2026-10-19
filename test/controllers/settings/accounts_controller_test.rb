require "test_helper"

class Settings::AccountsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:test_user)
    login_as(@user)
  end

  test "should show account section" do
    get settings_account_path
    assert_response :success
    assert_select "a[href='#{settings_account_email_path}']"
    assert_select "a[href='#{settings_account_handle_path}']"
    assert_select "a[href='#{settings_account_password_path}']"
  end

  test "should redirect to login when not authenticated" do
    logout(@user)
    get settings_account_path
    assert_redirected_to new_session_path
  end
end
