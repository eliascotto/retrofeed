class UserMailerPreview < ActionMailer::Preview
  def email_confirmation
    UserMailer.email_confirmation(User.first)
  end

  def email_change_confirmation
    user = User.first.tap do |u|
      u.fullname = "Jane Doe"
      u.unconfirmed_email = "new@example.com"
    end
    UserMailer.email_change_confirmation(user)
  end

  def email_password_reset
    UserMailer.email_password_reset(User.first)
  end

  def email_limit_alert
    admin = User.find_by(admin: true)
    UserMailer.email_limit_alert(admin, 90, "approaching")
  end
end
