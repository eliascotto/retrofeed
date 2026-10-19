class ConfirmationsController < ApplicationController
  layout "minimal"

  skip_before_action :require_login
  skip_before_action :require_handle

  before_action :set_user_by_token, only: :show
  before_action :require_unconfirmed_user, only: [ :new, :create, :edit, :update ]
  before_action :rate_limit_resend, only: :create

  def show
    # find_by_token_for returns nil for tokens that are invalid, tampered, or
    # past their baked-in expiry, so a single check covers all of those cases.
    if @user.nil?
      redirect_to new_session_path, alert: "Invalid or expired confirmation link"
      return
    end

    was_email_change = @user.email_confirmed? && @user.unconfirmed_email?

    @user.confirm_email!
    session[:user_id] = @user.id

    if was_email_change
      redirect_to settings_account_path, notice: "Your email has been updated."
    elsif @user.handle_setup_complete?
      redirect_to root_path, notice: "Email confirmed successfully. Welcome to Retrofeed!"
    else
      redirect_to new_handle_setup_path, notice: "Email confirmed successfully. Please choose a handle to continue."
    end
  end

  def new
  end

  def create
    user = current_unconfirmed_user

    if user.nil?
      redirect_to new_session_path, alert: "Please log in to resend confirmation"
      return
    end

    unless EmailTrackingService.can_send_email?
      flash.now[:alert] = "Unable to send email at this time. Please try again later."
      render :new, status: :service_unavailable
      return
    end

    begin
      user.track_confirmation_sent
      SendConfirmationEmailJob.perform_later(user.id)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      Rails.logger.error("Failed to send confirmation email for user #{user.id}: #{e.message}")
      flash.now[:alert] = "Unable to send confirmation email. Please try again."
      render :new, status: :unprocessable_entity
      return
    end

    redirect_to new_confirmation_path, notice: "Confirmation email sent. Please check your inbox."
  end

  def edit
  end

  def update
    user = current_unconfirmed_user

    if user.nil?
      redirect_to new_session_path, alert: "Please log in to change your email"
      return
    end

    new_email = params[:email]&.strip&.downcase

    if new_email.blank?
      flash.now[:alert] = "Email is required"
      render :edit, status: :unprocessable_entity
      return
    end

    unless URI::MailTo::EMAIL_REGEXP.match?(new_email)
      flash.now[:alert] = "Please enter a valid email address"
      render :edit, status: :unprocessable_entity
      return
    end

    if User.where.not(id: user.id).exists?(email: new_email)
      flash.now[:alert] = "This email is already in use"
      render :edit, status: :unprocessable_entity
      return
    end

    unless EmailTrackingService.can_send_email?
      flash.now[:alert] = "Unable to send email at this time. Please try again later."
      render :edit, status: :service_unavailable
      return
    end

    begin
      user.unconfirmed_email = new_email
      user.save!
      user.track_confirmation_sent
      SendConfirmationEmailJob.perform_later(user.id)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      Rails.logger.error("Failed to send confirmation email for user #{user.id}: #{e.message}")
      flash.now[:alert] = "Unable to send confirmation email. Please try again."
      render :edit, status: :unprocessable_entity
      return
    end

    redirect_to new_confirmation_path, notice: "Confirmation email sent to #{new_email}. Please check your inbox."
  end

  private
    def set_user_by_token
      token = params[:id]
      return if token.blank?

      @user = User.find_by_token_for(:email_confirmation, token)
    end

    def current_unconfirmed_user
      return nil unless session[:unconfirmed_user_id]

      User.unconfirmed.find_by(id: session[:unconfirmed_user_id])
    end

    def require_unconfirmed_user
      return if current_unconfirmed_user.present?

      redirect_to new_session_path, alert: "Please log in to continue"
    end

    def rate_limit_resend
      user = current_unconfirmed_user
      return if user.nil?

      if user.email_confirmation_sent_at.present? && user.email_confirmation_sent_at > 1.minute.ago
        flash.now[:alert] = "Please wait before requesting another confirmation email"
        render :new, status: :too_many_requests
      end
    end

    helper_method :current_unconfirmed_user
end
