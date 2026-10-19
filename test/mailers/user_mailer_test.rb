require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "email_confirmation sets correct to address" do
    user = users(:unconfirmed_user)

    email = UserMailer.email_confirmation(user)

    assert_equal [ user.email ], email.to
  end

  test "email_confirmation uses unconfirmed_email when present" do
    user = users(:unconfirmed_user)
    user.unconfirmed_email = "new_email@example.com"

    email = UserMailer.email_confirmation(user)

    assert_equal [ "new_email@example.com" ], email.to
  end

  test "email_confirmation sets correct subject" do
    user = users(:unconfirmed_user)

    email = UserMailer.email_confirmation(user)

    assert_equal "Confirm your email address", email.subject
  end

  test "email_confirmation includes a working confirmation link in body" do
    user = users(:unconfirmed_user)

    email = UserMailer.email_confirmation(user)

    token = email.body.encoded[%r{/confirmations/([^"'\s]+)}, 1]
    assert token.present?, "Expected a confirmation link in the email body"
    assert_equal user, User.find_by_token_for(:email_confirmation, token)
  end

  # ===== email_change_confirmation tests =====

  test "email_change_confirmation sends to unconfirmed_email" do
    user = users(:test_user)
    user.unconfirmed_email = "changed@example.com"

    email = UserMailer.email_change_confirmation(user)

    assert_equal [ "changed@example.com" ], email.to
  end

  test "email_change_confirmation sets correct subject" do
    user = users(:test_user)
    user.unconfirmed_email = "changed@example.com"

    email = UserMailer.email_change_confirmation(user)

    assert_equal "Confirm your new email address", email.subject
  end

  test "email_change_confirmation includes a working confirmation link in body" do
    user = users(:test_user)
    user.update_columns(unconfirmed_email: "changed@example.com")

    email = UserMailer.email_change_confirmation(user)

    token = email.body.encoded[%r{/confirmations/([^"'\s]+)}, 1]
    assert token.present?, "Expected a confirmation link in the email body"
    assert_equal user, User.find_by_token_for(:email_confirmation, token)
  end

  test "email_change_confirmation does not contain signup copy" do
    user = users(:test_user)
    user.unconfirmed_email = "changed@example.com"

    email = UserMailer.email_change_confirmation(user)

    assert_no_match "Thanks for signing up", email.body.encoded
  end

  test "email_change_confirmation includes fullname when present" do
    user = users(:test_user)
    user.fullname = "Jane Doe"
    user.unconfirmed_email = "changed@example.com"

    email = UserMailer.email_change_confirmation(user)

    assert_match "Jane Doe", email.body.encoded
  end

  test "email_change_confirmation includes contact-us warning" do
    user = users(:test_user)
    user.unconfirmed_email = "changed@example.com"

    email = UserMailer.email_change_confirmation(user)

    assert_match "didn't request this change", email.body.encoded
    assert_match "contact us immediately", email.body.encoded
  end

  test "email_change_confirmation falls back to email when unconfirmed_email is nil" do
    user = users(:test_user)

    email = UserMailer.email_change_confirmation(user)

    assert_equal [ user.email ], email.to
  end

  test "email_limit_alert sets correct to address" do
    admin = users(:admin)

    email = UserMailer.email_limit_alert(admin, 90, "approaching")

    assert_equal [ admin.email ], email.to
  end

  test "email_limit_alert includes count in subject for approaching status" do
    admin = users(:admin)

    email = UserMailer.email_limit_alert(admin, 90, "approaching")

    assert_match "approaching", email.subject
    assert_match "90", email.subject
  end

  test "email_limit_alert includes count in subject for over status" do
    admin = users(:admin)

    email = UserMailer.email_limit_alert(admin, 105, "over")

    assert_match "over", email.subject
    assert_match "105", email.subject
  end

  test "email_limit_alert body content differs based on status" do
    admin = users(:admin)

    approaching_email = UserMailer.email_limit_alert(admin, 90, "approaching")
    over_email = UserMailer.email_limit_alert(admin, 105, "over")

    assert_match "being approached", approaching_email.body.encoded
    assert_match "Consider upgrading", approaching_email.body.encoded

    assert_match "exceeded", over_email.body.encoded
    assert_match "No more emails can be sent", over_email.body.encoded
  end
end
