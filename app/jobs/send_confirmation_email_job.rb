class SendConfirmationEmailJob < ApplicationJob
  include EmailRateLimiting
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)

    if user.nil?
      Rails.logger.warn("SendConfirmationEmailJob: User #{user_id} not found, skipping")
      return
    end

    if user.email_confirmed?
      Rails.logger.info("SendConfirmationEmailJob: User #{user_id} already confirmed, skipping")
      return
    end

    deliver_tracked("email confirmation for user #{user_id}") do
      UserMailer.email_confirmation(user).deliver_now
    end
  end
end
