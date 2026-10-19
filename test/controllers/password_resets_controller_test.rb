require "test_helper"

class PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:test_user)
  end

  # create action - sends reset instructions for a known email
  test "create enqueues a reset email for a known email" do
    assert_enqueued_with(job: SendPasswordResetEmailJob, args: [ @user.id ]) do
      post password_reset_path, params: { email: @user.email }
    end

    assert_redirected_to new_session_path
    assert_equal "Check your email for reset instructions.", flash[:alert]
  end

  # create action - does not reveal whether an email exists
  test "create does not enqueue for an unknown email but responds the same" do
    assert_no_enqueued_jobs(only: SendPasswordResetEmailJob) do
      post password_reset_path, params: { email: "nobody@example.com" }
    end

    assert_redirected_to new_session_path
    assert_equal "Check your email for reset instructions.", flash[:alert]
  end

  # create action - blank email is a no-op
  test "create ignores a blank email" do
    assert_no_enqueued_jobs(only: SendPasswordResetEmailJob) do
      post password_reset_path, params: { email: "" }
    end

    assert_redirected_to new_session_path
  end

  # edit action - renders the form for a valid token
  test "edit renders the form for a valid token" do
    token = @user.generate_token_for(:password_reset)

    get edit_password_reset_path(token: token)

    assert_response :success
  end

  # edit action - rejects an invalid token
  test "edit rejects an invalid token" do
    get edit_password_reset_path(token: "not-a-real-token")

    assert_redirected_to new_session_path
    assert_equal "Invalid or expired reset link.", flash[:alert]
  end

  # edit action - rejects an expired token
  test "edit rejects an expired token" do
    token = @user.generate_token_for(:password_reset)

    travel User::PASSWORD_RESET_TOKEN_TTL + 1.minute do
      get edit_password_reset_path(token: token)
    end

    assert_redirected_to new_session_path
    assert_equal "Invalid or expired reset link.", flash[:alert]
  end

  # update action - resets the password with a valid token
  test "update sets a new password with a valid token" do
    token = @user.generate_token_for(:password_reset)

    patch password_reset_path, params: {
      token: token,
      password: "new-password-123",
      password_confirmation: "new-password-123"
    }

    assert_redirected_to new_session_path
    assert_equal "Password updated. Please log in.", flash[:alert]
    assert @user.reload.authenticate("new-password-123")
  end

  # update action - the token is single-use (invalidated by the password change)
  test "update token cannot be reused after the password changes" do
    token = @user.generate_token_for(:password_reset)

    patch password_reset_path, params: {
      token: token,
      password: "new-password-123",
      password_confirmation: "new-password-123"
    }

    # The same token should no longer resolve to the user.
    assert_nil User.find_by_token_for(:password_reset, token)

    patch password_reset_path, params: {
      token: token,
      password: "another-password-456",
      password_confirmation: "another-password-456"
    }

    assert_redirected_to new_session_path
    assert_equal "Invalid or expired reset link.", flash[:alert]
    assert @user.reload.authenticate("new-password-123")
  end

  # update action - rejects an invalid token
  test "update rejects an invalid token" do
    patch password_reset_path, params: {
      token: "not-a-real-token",
      password: "new-password-123",
      password_confirmation: "new-password-123"
    }

    assert_redirected_to new_session_path
    assert_equal "Invalid or expired reset link.", flash[:alert]
  end
end
