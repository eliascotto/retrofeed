require "test_helper"

class SettingsNavigationTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:test_user)
    login_as(@user)
  end

  test "can navigate from index to account section" do
    get settings_path
    assert_response :success

    get settings_account_path
    assert_response :success
    # Back button uses onclick with history fallback to settings_path
    assert_select "button.btn-circle"
  end

  test "can navigate from account to handle subsection" do
    get settings_account_path
    assert_response :success

    get settings_account_handle_path
    assert_response :success
    # Back button uses onclick with history fallback to settings_account_path
    assert_select "button.btn-circle"
  end

  test "can update handle and return to account section" do
    get settings_account_handle_path
    assert_response :success

    new_handle = "updatedhandle"
    patch settings_account_handle_path, params: {
      user: { handle: new_handle }
    }
    assert_redirected_to settings_account_path

    follow_redirect!
    assert_response :success
    assert_select "a[href='#{settings_account_handle_path}']"
  end

  test "can navigate to appearance page with theme options" do
    get settings_path
    assert_response :success

    get settings_appearance_path
    assert_response :success
    # Theme settings are shown directly on the appearance page
    assert_select "input[name='theme'][value='system']"
    assert_select "input[name='theme'][value='light']"
    assert_select "input[name='theme'][value='dark']"
  end

  test "back navigation works correctly" do
    # Navigate deep into settings
    get settings_account_handle_path
    assert_response :success
    # Back button uses onclick with history fallback
    assert_select "button.btn-circle"

    # Go back to account
    get settings_account_path
    assert_response :success
    assert_select "button.btn-circle"

    # Go back to main settings
    get settings_path
    assert_response :success
  end
end
