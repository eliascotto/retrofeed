class UsersController < ApplicationController
  layout "minimal"

  skip_before_action :require_login, only: [ :new, :create ]
  skip_before_action :require_handle, only: [ :new, :create ]

  rate_limit to: 5, within: 1.hour, only: :create

  def new
  end

  def create
    email = params[:email]&.strip&.downcase
    password = params[:password]

    if email.blank? || password.blank?
      flash.now[:alert] = "Email and password are required"
      render :new, status: :unprocessable_entity
      return
    end

    if password.length < 8
      flash.now[:alert] = "Password must be at least 8 characters long"
      render :new, status: :unprocessable_entity
      return
    end

    if User.exists?(email: email)
      flash.now[:alert] = "An account with this email already exists"
      render :new, status: :unprocessable_entity
      return
    end

    unless EmailTrackingService.can_send_email?
      flash.now[:alert] = "Unable to complete registration at this time. Please try again later."
      render :new, status: :service_unavailable
      return
    end

    # Create user without handle - handle will be set after email confirmation
    user = User.new(
      email: email,
      password: password,
      email_confirmed_at: nil
    )

    if user.save
      begin
        user.track_confirmation_sent
        SendConfirmationEmailJob.perform_later(user.id)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        Rails.logger.error("Failed to send confirmation email for user #{user.id}: #{e.message}")
        session[:unconfirmed_user_id] = user.id
        redirect_to new_confirmation_path, alert: "Account created, but we couldn't send the confirmation email. Please try resending it."
        return
      end

      session[:unconfirmed_user_id] = user.id
      redirect_to new_confirmation_path, notice: "Account created! Please check your email to confirm your account."
    else
      flash.now[:alert] = user.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end
end
