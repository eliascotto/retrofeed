require "test_helper"

class Settings::Account::HandleControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:test_user)
    login_as(@user)
  end

  test "should show handle form" do
    get settings_account_handle_path
    assert_response :success
    assert_select "input[name='user[handle]']"
  end

  test "should successfully update handle" do
    new_handle = "newhandle"
    patch settings_account_handle_path, params: {
      user: {
        handle: new_handle
      }
    }
    assert_redirected_to settings_account_path
    assert_equal "Handle updated successfully", flash[:notice]
    @user.reload
    assert_equal new_handle, @user.handle
  end

  test "should not update handle if it already exists" do
    other_user = users(:other_user)
    patch settings_account_handle_path, params: {
      user: {
        handle: other_user.handle
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
    @user.reload
    assert_not_equal other_user.handle, @user.handle
  end

  test "should not allow empty handle" do
    patch settings_account_handle_path, params: {
      user: {
        handle: ""
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
    @user.reload
    assert_not_equal "", @user.handle
  end

  test "should redirect to login when not authenticated" do
    logout(@user)
    get settings_account_handle_path
    assert_redirected_to new_session_path
  end
end
