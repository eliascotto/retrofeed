require "test_helper"

class UserEmailConfirmationTest < ActiveSupport::TestCase
  # ===== CONFIRMATION_TOKEN_TTL constant =====

  test "CONFIRMATION_TOKEN_TTL is 24 hours" do
    assert_equal 24.hours, User::CONFIRMATION_TOKEN_TTL
  end

  # ===== email_confirmed? tests =====

  test "email_confirmed? returns true when email_confirmed_at is present" do
    user = users(:test_user)
    assert user.email_confirmed?
  end

  test "email_confirmed? returns false when email_confirmed_at is nil" do
    user = users(:unconfirmed_user)
    assert_not user.email_confirmed?
  end

  # ===== unconfirmed_email? tests =====

  test "unconfirmed_email? returns true when unconfirmed_email is present" do
    user = users(:test_user)
    user.unconfirmed_email = "new@example.com"
    assert user.unconfirmed_email?
  end

  test "unconfirmed_email? returns false when unconfirmed_email is nil" do
    user = users(:test_user)
    user.unconfirmed_email = nil
    assert_not user.unconfirmed_email?
  end

  test "unconfirmed_email? returns false when unconfirmed_email is blank" do
    user = users(:test_user)
    user.unconfirmed_email = ""
    assert_not user.unconfirmed_email?
  end

  # ===== email_confirmation token (generates_token_for) tests =====

  test "email_confirmation token round-trips through find_by_token_for" do
    user = users(:unconfirmed_user)

    token = user.generate_token_for(:email_confirmation)

    assert_equal user, User.find_by_token_for(:email_confirmation, token)
  end

  test "email_confirmation token is rejected once expired" do
    user = users(:unconfirmed_user)
    token = user.generate_token_for(:email_confirmation)

    travel User::CONFIRMATION_TOKEN_TTL + 1.minute do
      assert_nil User.find_by_token_for(:email_confirmation, token)
    end
  end

  test "email_confirmation token is single-use after confirm_email!" do
    user = users(:unconfirmed_user)
    token = user.generate_token_for(:email_confirmation)

    user.confirm_email!

    assert_nil User.find_by_token_for(:email_confirmation, token)
  end

  test "email_confirmation token is invalidated when the target email changes" do
    user = users(:unconfirmed_user)
    token = user.generate_token_for(:email_confirmation)

    user.update_columns(unconfirmed_email: "different@example.com")

    assert_nil User.find_by_token_for(:email_confirmation, token)
  end

  # ===== track_confirmation_sent tests =====

  test "track_confirmation_sent sets email_confirmation_sent_at" do
    user = users(:test_user)
    user.update_columns(email_confirmation_sent_at: nil)

    freeze_time do
      user.track_confirmation_sent
      assert_equal Time.current, user.email_confirmation_sent_at
      assert_equal Time.current, user.reload.email_confirmation_sent_at
    end
  end

  # ===== confirm_email! tests =====

  test "confirm_email! sets email_confirmed_at" do
    user = users(:unconfirmed_user)
    assert_nil user.email_confirmed_at

    freeze_time do
      user.confirm_email!
      assert_equal Time.current, user.email_confirmed_at
    end
  end

  test "confirm_email! moves unconfirmed_email to email when present" do
    user = users(:unconfirmed_user)
    new_email = "newemail@example.com"
    user.unconfirmed_email = new_email
    user.save!

    user.confirm_email!
    user.reload

    assert_equal new_email, user.email
    assert_nil user.unconfirmed_email
  end

  test "confirm_email! keeps original email when unconfirmed_email is not present" do
    user = users(:unconfirmed_user)
    original_email = user.email
    user.unconfirmed_email = nil
    user.save!

    user.confirm_email!
    user.reload

    assert_equal original_email, user.email
  end

  # ===== confirmed scope tests =====

  test "confirmed scope returns users with email_confirmed_at present" do
    confirmed_users = User.confirmed

    assert_includes confirmed_users, users(:test_user)
    assert_includes confirmed_users, users(:admin)
    assert_not_includes confirmed_users, users(:unconfirmed_user)
  end

  # ===== unconfirmed scope tests =====

  test "unconfirmed scope returns users with email_confirmed_at nil" do
    unconfirmed_users = User.unconfirmed

    assert_includes unconfirmed_users, users(:unconfirmed_user)
    assert_not_includes unconfirmed_users, users(:test_user)
    assert_not_includes unconfirmed_users, users(:admin)
  end
end
