class SendPasswordResetEmailJob < ApplicationJob
  include EmailRateLimiting
  queue_as :default

  def perform(user_id)
    Rails.logger.tagged("SendPasswordResetEmailJob") do
      user = User.find_by(id: user_id)

      if user.nil?
        Rails.logger.warn("User #{user_id} not found, skipping")
        return
      end

      deliver_tracked("email password reset for user #{user_id}") do
        UserMailer.email_password_reset(user).deliver_now
      end
    end
  end
end
