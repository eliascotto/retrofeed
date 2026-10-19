class Settings::Account::EmailsController < ApplicationController
  def show
    @user = current_user
  end

  def update
    @user = current_user
    new_email = params[:user][:email].to_s.strip.downcase

    if new_email.blank?
      @user.errors.add(:email, "can't be blank")
      render :show, status: :unprocessable_entity
      return
    end

    unless URI::MailTo::EMAIL_REGEXP.match?(new_email)
      @user.errors.add(:email, "is invalid")
      render :show, status: :unprocessable_entity
      return
    end

    if User.where.not(id: @user.id).exists?(email: new_email)
      @user.errors.add(:email, "has already been taken")
      render :show, status: :unprocessable_entity
      return
    end

    unless EmailTrackingService.can_send_email?
      @user.errors.add(:base, "Unable to send email at this time. Please try again later.")
      render :show, status: :service_unavailable
      return
    end

    begin
      @user.update!(unconfirmed_email: new_email)
      @user.track_confirmation_sent
      SendEmailChangeConfirmationJob.perform_later(@user.id)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      Rails.logger.error("Failed to initiate email change for user #{@user.id}: #{e.message}")
      @user.errors.add(:base, "Unable to send confirmation email. Please try again.")
      render :show, status: :unprocessable_entity
      return
    end

    redirect_to settings_account_path, notice: "Confirmation email sent to #{new_email}. Please check your inbox."
  end
end
