require "test_helper"

class Settings::Account::PasswordsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:test_user)
    login_as(@user)
  end

  test "should show password form" do
    get settings_account_password_path
    assert_response :success
    assert_select "input[name='current_password']"
    assert_select "input[name='user[password]']"
    assert_select "input[name='user[password_confirmation]']"
  end

  test "should successfully update password with correct current password" do
    new_password = "newpassword123"
    patch settings_account_password_path, params: {
      current_password: "password123",
      user: {
        password: new_password,
        password_confirmation: new_password
      }
    }
    assert_redirected_to settings_account_path
    assert_equal "Password updated successfully", flash[:notice]

    # Verify new password works
    delete session_path(@user.id)
    post sessions_path, params: { email: @user.email, password: new_password }
    assert_redirected_to root_path
  end

  test "should not update password if it matches current password" do
    patch settings_account_password_path, params: {
      current_password: "password123",
      user: {
        password: "password123",
        password_confirmation: "password123"
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"

    # Verify old password still works
    delete session_path(@user.id)
    login_as(@user)
    assert_redirected_to root_path
  end

  test "should not update password if confirmation does not match" do
    patch settings_account_password_path, params: {
      current_password: "password123",
      user: {
        password: "newpassword123",
        password_confirmation: "differentpassword"
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"

    # Verify old password still works
    delete session_path(@user.id)
    login_as(@user)
    assert_redirected_to root_path
  end

  test "should require current password when changing password" do
    patch settings_account_password_path, params: {
      user: {
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
    assert_select ".alert-error", text: /required to change your password/i

    # Verify old password still works
    delete session_path(@user.id)
    login_as(@user)
    assert_redirected_to root_path
  end

  test "should not update password with incorrect current password" do
    patch settings_account_password_path, params: {
      current_password: "wrongpassword",
      user: {
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
    assert_select ".alert-error", text: /incorrect/i

    # Verify old password still works
    delete session_path(@user.id)
    login_as(@user)
    assert_redirected_to root_path
  end

  test "should not update password if it is too short" do
    patch settings_account_password_path, params: {
      current_password: "password123",
      user: {
        password: "short",
        password_confirmation: "short"
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
    assert_select ".alert-error", text: /too short/i

    # Verify old password still works
    delete session_path(@user.id)
    login_as(@user)
    assert_redirected_to root_path
  end

  test "should not update password if it is too long" do
    long_password = "a" * 73
    patch settings_account_password_path, params: {
      current_password: "password123",
      user: {
        password: long_password,
        password_confirmation: long_password
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
    assert_select ".alert-error", text: /too long/i

    # Verify old password still works
    delete session_path(@user.id)
    login_as(@user)
    assert_redirected_to root_path
  end

  test "should redirect to login when not authenticated" do
    delete session_path(@user.id)
    get settings_account_password_path
    assert_redirected_to new_session_path
  end
end
