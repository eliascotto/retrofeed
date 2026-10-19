require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    # Ensure email sending is always allowed in tests
    @original_can_send = EmailTrackingService.method(:can_send_email?)
    EmailTrackingService.define_singleton_method(:can_send_email?) { true }
  end

  teardown do
    EmailTrackingService.define_singleton_method(:can_send_email?, @original_can_send)
  end

  # new action - renders signup form
  test "new renders signup form" do
    get new_user_path

    assert_response :success
    assert_select "h1", "Create a new RetroFeed account"
  end

  # create action - validates inputs
  test "create requires email and password" do
    post users_path, params: { email: "", password: "" }

    assert_response :unprocessable_entity
    assert_equal "Email and password are required", flash[:alert]
  end

  test "create requires password of at least 8 characters" do
    post users_path, params: { email: "new@example.com", password: "short" }

    assert_response :unprocessable_entity
    assert_equal "Password must be at least 8 characters long", flash[:alert]
  end

  test "create rejects existing email" do
    user = users(:test_user)

    post users_path, params: { email: user.email, password: "password123" }

    assert_response :unprocessable_entity
    assert_equal "An account with this email already exists", flash[:alert]
  end

  test "create creates user without handle and redirects to confirmation page" do
    assert_difference -> { User.count }, 1 do
      post users_path, params: { email: "newuser@example.com", password: "password123" }
    end

    assert_redirected_to new_confirmation_path
    assert_equal "Account created! Please check your email to confirm your account.", flash[:notice]

    user = User.find_by(email: "newuser@example.com")
    assert user.present?
    assert_nil user.handle
    assert user.email_confirmation_sent_at.present?
    assert_equal user.id, session[:unconfirmed_user_id]
  end

  test "create sends confirmation email" do
    assert_enqueued_with(job: SendConfirmationEmailJob) do
      post users_path, params: { email: "emailtest@example.com", password: "password123" }
    end
  end

  test "create handles confirmation send failure gracefully" do
    # Override track_confirmation_sent to raise an exception
    original_method = User.instance_method(:track_confirmation_sent)
    User.define_method(:track_confirmation_sent) do
      raise ActiveRecord::RecordInvalid.new(self)
    end

    begin
      assert_no_enqueued_jobs(only: SendConfirmationEmailJob) do
        post users_path, params: { email: "failuser@example.com", password: "password123" }
      end

      assert_redirected_to new_confirmation_path
      assert_equal "Account created, but we couldn't send the confirmation email. Please try resending it.", flash[:alert]

      # User should still be created
      user = User.find_by(email: "failuser@example.com")
      assert user.present?
      assert_equal user.id, session[:unconfirmed_user_id]
    ensure
      User.define_method(:track_confirmation_sent, original_method)
    end
  end

  test "create fails when email service is unavailable" do
    EmailTrackingService.define_singleton_method(:can_send_email?) { false }

    assert_no_difference -> { User.count } do
      post users_path, params: { email: "emailfail@example.com", password: "password123" }
    end

    assert_response :service_unavailable
    assert_equal "Unable to complete registration at this time. Please try again later.", flash[:alert]
  end

  test "create normalizes email to lowercase" do
    post users_path, params: { email: "UPPERCASE@EXAMPLE.COM", password: "password123" }

    user = User.find_by(email: "uppercase@example.com")
    assert user.present?
    assert_equal "uppercase@example.com", user.email
  end
end
