class UserMailer < ApplicationMailer
  def email_confirmation(user)
    @user = user
    @confirmation_url = confirmation_url(user.generate_token_for(:email_confirmation))
    @expires_in = User::CONFIRMATION_TOKEN_TTL

    mail(
      to: user.unconfirmed_email || user.email,
      subject: "Confirm your email address"
    )
  end

  def email_change_confirmation(user)
    @user = user
    @confirmation_url = confirmation_url(user.generate_token_for(:email_confirmation))
    @expires_in = User::CONFIRMATION_TOKEN_TTL

    mail(
      to: user.unconfirmed_email || user.email,
      subject: "Confirm your new email address"
    )
  end

  def email_password_reset(user)
    @user = user
    @reset_url = edit_password_reset_url(token: user.generate_token_for(:password_reset))
    @expires_in = User::PASSWORD_RESET_TOKEN_TTL

    mail(
      to: user.email,
      subject: "Reset your password"
    )
  end

  def email_limit_alert(admin, count, status)
    @admin = admin
    @count = count
    @status = status
    @limit = EmailTrackingService::DAILY_LIMIT

    mail(
      to: admin.email,
      subject: "Email limit #{status}: #{count}/#{@limit} emails sent today"
    )
  end
end
