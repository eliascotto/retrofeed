class SendEmailChangeConfirmationJob < ApplicationJob
  include EmailRateLimiting
  queue_as :default

  def perform(user_id)
    Rails.logger.tagged("SendEmailChangeConfirmationJob") do
      user = User.find_by(id: user_id)

      if user.nil?
        Rails.logger.warn("User #{user_id} not found, skipping")
        return
      end

      unless user.unconfirmed_email?
        Rails.logger.info("User #{user_id} has no pending email change, skipping")
        return
      end

      deliver_tracked("email change confirmation for user #{user_id}") do
        UserMailer.email_change_confirmation(user).deliver_now
      end
    end
  end
end
