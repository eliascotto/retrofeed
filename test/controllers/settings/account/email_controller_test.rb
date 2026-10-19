require "test_helper"

class Settings::Account::EmailControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = users(:test_user)
    login_as(@user)
  end

  test "should show email form" do
    get settings_account_email_path
    assert_response :success
    assert_select "input[name='user[email]']"
  end

  test "should set unconfirmed_email and send confirmation instead of updating email directly" do
    new_email = "newemail@example.com"
    original_email = @user.email

    assert_enqueued_with(job: SendEmailChangeConfirmationJob) do
      patch settings_account_email_path, params: {
        user: { email: new_email }
      }
    end

    assert_redirected_to settings_account_path
    assert_match "Confirmation email sent to #{new_email}", flash[:notice]

    @user.reload
    assert_equal original_email, @user.email, "Email should not change until confirmed"
    assert_equal new_email, @user.unconfirmed_email
    assert @user.email_confirmation_sent_at.present?
  end

  test "should not update email if it already exists" do
    other_user = users(:other_user)
    patch settings_account_email_path, params: {
      user: {
        email: other_user.email
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
    @user.reload
    assert_nil @user.unconfirmed_email
  end

  test "should not allow invalid email" do
    patch settings_account_email_path, params: {
      user: {
        email: "invalid-email"
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
  end

  test "should not allow blank email" do
    patch settings_account_email_path, params: {
      user: {
        email: ""
      }
    }
    assert_response :unprocessable_entity
    assert_select ".alert-error"
  end

  test "should redirect to login when not authenticated" do
    delete session_path(@user.id)
    get settings_account_email_path
    assert_redirected_to new_session_path
  end

  test "shows pending email change notice when unconfirmed_email is set" do
    @user.update_columns(unconfirmed_email: "pending@example.com")

    get settings_account_email_path
    assert_response :success
    assert_select ".alert-info", /pending@example.com/
  end

  test "email is updated after confirming via confirmation link" do
    new_email = "confirmed-change@example.com"

    patch settings_account_email_path, params: {
      user: { email: new_email }
    }

    @user.reload
    token = @user.generate_token_for(:email_confirmation)

    get confirmation_path(token)

    assert_redirected_to settings_account_path
    assert_equal "Your email has been updated.", flash[:notice]

    @user.reload
    assert_equal new_email, @user.email
    assert_nil @user.unconfirmed_email
  end
end
