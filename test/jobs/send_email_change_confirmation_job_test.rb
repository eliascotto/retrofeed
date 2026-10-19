require "test_helper"

class SendEmailChangeConfirmationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @user = users(:test_user)
    @user.update_columns(unconfirmed_email: "newemail@example.com")
    @user.track_confirmation_sent

    @original_can_send = EmailTrackingService.method(:can_send_email?)
    @original_increment = EmailTrackingService.method(:increment_daily_count)
    @original_over_limit = EmailTrackingService.method(:over_limit?)
    @original_approaching_limit = EmailTrackingService.method(:approaching_limit?)

    EmailTrackingService.define_singleton_method(:can_send_email?) { true }
    EmailTrackingService.define_singleton_method(:increment_daily_count) { true }
    EmailTrackingService.define_singleton_method(:over_limit?) { false }
    EmailTrackingService.define_singleton_method(:approaching_limit?) { false }

    @mail_message = DeliverExpectation.new
  end

  teardown do
    EmailTrackingService.define_singleton_method(:can_send_email?, @original_can_send)
    EmailTrackingService.define_singleton_method(:increment_daily_count, @original_increment)
    EmailTrackingService.define_singleton_method(:over_limit?, @original_over_limit)
    EmailTrackingService.define_singleton_method(:approaching_limit?, @original_approaching_limit)
  end

  def stub_mailer(&block)
    stub_singleton(UserMailer, :email_change_confirmation, @mail_message, &block)
  end

  test "does not send email if user not found" do
    assert_no_emails do
      SendEmailChangeConfirmationJob.perform_now(-1)
    end
  end

  test "does not send email if no pending email change" do
    @user.update_columns(unconfirmed_email: nil)

    assert_no_emails do
      SendEmailChangeConfirmationJob.perform_now(@user.id)
    end
  end

  test "sends email for confirmed user with pending email change" do
    stub_mailer do
      SendEmailChangeConfirmationJob.perform_now(@user.id)
    end

    assert @mail_message.verify
  end

  test "does not skip when user is already email-confirmed" do
    assert @user.email_confirmed?, "Precondition: user should be confirmed"

    stub_mailer do
      SendEmailChangeConfirmationJob.perform_now(@user.id)
    end

    assert @mail_message.verify
  end

  test "does not send email if over limit" do
    EmailTrackingService.define_singleton_method(:can_send_email?) { false }

    assert_no_emails do
      SendEmailChangeConfirmationJob.perform_now(@user.id)
    end
  end

  test "increments daily count after sending" do
    incremented = false
    EmailTrackingService.define_singleton_method(:increment_daily_count) { incremented = true }

    stub_mailer do
      SendEmailChangeConfirmationJob.perform_now(@user.id)
    end

    assert incremented, "Expected increment_daily_count to be called"
  end

  test "triggers alert job when approaching limit" do
    EmailTrackingService.define_singleton_method(:approaching_limit?) { true }

    stub_mailer do
      assert_enqueued_with(job: EmailLimitAlertJob, args: [ "approaching" ]) do
        SendEmailChangeConfirmationJob.perform_now(@user.id)
      end
    end
  end

  test "triggers alert job when over limit" do
    EmailTrackingService.define_singleton_method(:over_limit?) { true }

    stub_mailer do
      assert_enqueued_with(job: EmailLimitAlertJob, args: [ "over" ]) do
        SendEmailChangeConfirmationJob.perform_now(@user.id)
      end
    end
  end
end
