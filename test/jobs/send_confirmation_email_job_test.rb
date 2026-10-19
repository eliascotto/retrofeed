require "test_helper"

class SendConfirmationEmailJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @unconfirmed_user = users(:unconfirmed_user)
    @confirmed_user = users(:test_user)

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
    stub_singleton(UserMailer, :email_confirmation, @mail_message, &block)
  end

  test "does not send email if user not found" do
    assert_no_emails do
      SendConfirmationEmailJob.perform_now(-1)
    end
  end

  test "does not send email if user already confirmed" do
    assert_no_emails do
      SendConfirmationEmailJob.perform_now(@confirmed_user.id)
    end
  end

  test "sends email for valid unconfirmed user with valid token" do
    stub_mailer do
      SendConfirmationEmailJob.perform_now(@unconfirmed_user.id)
    end

    assert @mail_message.verify
  end

  test "does not send email if over limit" do
    EmailTrackingService.define_singleton_method(:can_send_email?) { false }

    assert_no_emails do
      SendConfirmationEmailJob.perform_now(@unconfirmed_user.id)
    end
  end

  test "increments daily count after sending" do
    incremented = false
    EmailTrackingService.define_singleton_method(:increment_daily_count) { incremented = true }

    stub_mailer do
      SendConfirmationEmailJob.perform_now(@unconfirmed_user.id)
    end

    assert incremented, "Expected increment_daily_count to be called"
  end

  test "triggers alert job when approaching limit" do
    EmailTrackingService.define_singleton_method(:approaching_limit?) { true }

    stub_mailer do
      assert_enqueued_with(job: EmailLimitAlertJob, args: [ "approaching" ]) do
        SendConfirmationEmailJob.perform_now(@unconfirmed_user.id)
      end
    end
  end

  test "triggers alert job when over limit" do
    EmailTrackingService.define_singleton_method(:over_limit?) { true }

    stub_mailer do
      assert_enqueued_with(job: EmailLimitAlertJob, args: [ "over" ]) do
        SendConfirmationEmailJob.perform_now(@unconfirmed_user.id)
      end
    end
  end
end
