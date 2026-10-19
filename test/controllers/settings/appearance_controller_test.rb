require "test_helper"

class Settings::AppearanceControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:test_user)
    login_as(@user)
  end

  test "should show appearance section with theme options" do
    get settings_appearance_path
    assert_response :success
    # Theme settings are shown directly on the appearance page via SegmentedControlComponent
    assert_select "input[name='theme'][value='system']"
    assert_select "input[name='theme'][value='light']"
    assert_select "input[name='theme'][value='dark']"
  end

  test "should redirect to login when not authenticated" do
    delete session_path(@user.id)
    get settings_appearance_path
    assert_redirected_to new_session_path
  end
end
