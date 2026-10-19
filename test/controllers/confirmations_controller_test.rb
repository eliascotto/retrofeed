require "test_helper"

class ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    # Ensure email sending is always allowed in tests
    @original_can_send = EmailTrackingService.method(:can_send_email?)
    EmailTrackingService.define_singleton_method(:can_send_email?) { true }
  end

  teardown do
    EmailTrackingService.define_singleton_method(:can_send_email?, @original_can_send)
  end

  # show action - confirms valid token and logs user in
  test "show confirms email with valid token and redirects to root for user with handle" do
    user = users(:unconfirmed_user)

    get confirmation_path(user.generate_token_for(:email_confirmation))

    assert_redirected_to root_path
    assert_equal "Email confirmed successfully. Welcome to Retrofeed!", flash[:notice]
    assert_equal user.id, session[:user_id]

    user.reload
    assert user.email_confirmed_at.present?
  end

  test "show confirms email and redirects to handle setup for user without handle" do
    user = users(:unconfirmed_no_handle)

    get confirmation_path(user.generate_token_for(:email_confirmation))

    assert_redirected_to new_handle_setup_path
    assert_equal "Email confirmed successfully. Please choose a handle to continue.", flash[:notice]
    assert_equal user.id, session[:user_id]

    user.reload
    assert user.email_confirmed_at.present?
  end

  # show action - confirms email change for already-confirmed user
  test "show confirms email change and redirects to settings for confirmed user with unconfirmed_email" do
    user = users(:test_user)
    user.update_columns(unconfirmed_email: "changed@example.com")

    get confirmation_path(user.generate_token_for(:email_confirmation))

    assert_redirected_to settings_account_path
    assert_equal "Your email has been updated.", flash[:notice]
    assert_equal user.id, session[:user_id]

    user.reload
    assert_equal "changed@example.com", user.email
    assert_nil user.unconfirmed_email
  end

  # show action - redirects with error for invalid token
  test "show redirects with error for invalid token" do
    get confirmation_path("invalid_token")

    assert_redirected_to new_session_path
    assert_equal "Invalid or expired confirmation link", flash[:alert]
    assert_nil session[:user_id]
  end

  # show action - redirects with error for expired token
  test "show redirects with error for expired token" do
    user = users(:unconfirmed_user)
    token = user.generate_token_for(:email_confirmation)

    travel User::CONFIRMATION_TOKEN_TTL + 1.minute do
      get confirmation_path(token)
    end

    assert_redirected_to new_session_path
    assert_equal "Invalid or expired confirmation link", flash[:alert]
    assert_nil session[:user_id]
  end

  # new action - requires unconfirmed user session
  test "new requires unconfirmed user session" do
    get "/confirmations/new"

    assert_redirected_to new_session_path
  end

  test "new renders form when unconfirmed user session exists" do
    user = users(:unconfirmed_user)
    login_as(user)
    follow_redirect!

    get new_confirmation_path

    assert_response :success
  end

  # create action - resends confirmation email
  test "create resends confirmation email" do
    user = users(:unconfirmed_user)
    user.update!(email_confirmation_sent_at: 2.minutes.ago)
    login_as(user)

    assert_enqueued_with(job: SendConfirmationEmailJob) do
      post confirmations_path
    end

    assert_redirected_to new_confirmation_path
    assert_equal "Confirmation email sent. Please check your inbox.", flash[:notice]
  end

  # create action - rate limits resend requests (within 1 minute)
  test "create rate limits resend requests within 1 minute" do
    user = users(:unconfirmed_user)
    user.update!(email_confirmation_sent_at: 30.seconds.ago)
    login_as(user)

    post confirmations_path

    assert_response :too_many_requests
    assert_equal "Please wait before requesting another confirmation email", flash[:alert]
  end

  # edit action - requires unconfirmed user session
  test "edit requires unconfirmed user session" do
    get "/confirmations/edit"

    assert_redirected_to new_session_path
  end

  test "edit renders form when unconfirmed user session exists" do
    user = users(:unconfirmed_user)
    login_as(user)

    get edit_confirmation_path(user)

    assert_response :success
  end

  # update action - validates email format
  test "update validates email format" do
    user = users(:unconfirmed_user)
    login_as(user)

    patch confirmation_path(user), params: { email: "invalid-email" }

    assert_response :unprocessable_entity
    assert_equal "Please enter a valid email address", flash[:alert]
  end

  test "update validates email is required" do
    user = users(:unconfirmed_user)
    login_as(user)

    patch confirmation_path(user), params: { email: "" }

    assert_response :unprocessable_entity
    assert_equal "Email is required", flash[:alert]
  end

  # update action - validates email uniqueness
  test "update validates email uniqueness" do
    user = users(:unconfirmed_user)
    existing_user = users(:test_user)
    login_as(user)

    patch confirmation_path(user), params: { email: existing_user.email }

    assert_response :unprocessable_entity
    assert_equal "This email is already in use", flash[:alert]
  end

  # update action - sends new confirmation with new email
  test "update sends new confirmation with new email" do
    user = users(:unconfirmed_user)
    new_email = "newemail@example.com"
    login_as(user)

    assert_enqueued_with(job: SendConfirmationEmailJob) do
      patch confirmation_path(user), params: { email: new_email }
    end

    assert_redirected_to new_confirmation_path
    assert_equal "Confirmation email sent to #{new_email}. Please check your inbox.", flash[:notice]

    user.reload
    assert_equal new_email, user.unconfirmed_email
  end

  # create action - handles a send-tracking failure
  test "create handles confirmation send failure gracefully" do
    user = users(:unconfirmed_user)
    user.update!(email_confirmation_sent_at: 2.minutes.ago)
    login_as(user)

    # Override track_confirmation_sent to raise an exception
    original_method = User.instance_method(:track_confirmation_sent)
    User.define_method(:track_confirmation_sent) do
      raise ActiveRecord::RecordInvalid.new(self)
    end

    begin
      assert_no_enqueued_jobs(only: SendConfirmationEmailJob) do
        post confirmations_path
      end

      assert_response :unprocessable_entity
      assert_equal "Unable to send confirmation email. Please try again.", flash[:alert]
    ensure
      User.define_method(:track_confirmation_sent, original_method)
    end
  end

  # update action - handles a send-tracking failure
  test "update handles confirmation send failure gracefully" do
    user = users(:unconfirmed_user)
    login_as(user)

    # Override track_confirmation_sent to raise an exception
    original_method = User.instance_method(:track_confirmation_sent)
    User.define_method(:track_confirmation_sent) do
      raise ActiveRecord::RecordInvalid.new(self)
    end

    begin
      assert_no_enqueued_jobs(only: SendConfirmationEmailJob) do
        patch confirmation_path(user), params: { email: "failchange@example.com" }
      end

      assert_response :unprocessable_entity
      assert_equal "Unable to send confirmation email. Please try again.", flash[:alert]
    ensure
      User.define_method(:track_confirmation_sent, original_method)
    end
  end
end
