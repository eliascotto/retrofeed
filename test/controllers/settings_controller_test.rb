require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:test_user)
    login_as(@user)
  end

  test "should show settings index page when authenticated" do
    get settings_path
    assert_response :success
    assert_select "h2", text: @user.fullname.presence || @user.handle
    assert_select "a[href='#{settings_account_path}']"
    assert_select "a[href='#{settings_appearance_path}']"
  end

  test "should redirect to login when not authenticated" do
    logout(@user)
    get settings_path
    assert_redirected_to new_session_path
  end
end
