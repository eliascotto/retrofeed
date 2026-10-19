class PasswordResetsController < ApplicationController
  layout "minimal"

  skip_before_action :require_login
  skip_before_action :require_handle

  rate_limit to: 3, within: 3.minutes, with: :redirect_to_many_req, only: :create

  def new
  end

  def create
    Rails.logger.tagged("PasswordResetsController") do
      if params[:email].blank?
        Rails.logger.warn { "Empty password reset email, skipping" }
        default_redirect_to and return
      end

      user = User.find_by(email: params[:email])

      if user.nil?
        Rails.logger.warn { "User email not found, skipping" }
        default_redirect_to and return
      end

      # The reset token is a signed, self-expiring value generated at send time,
      # so there is nothing to persist here. Abuse is bounded by the rate_limit.
      SendPasswordResetEmailJob.perform_later(user.id)
      default_redirect_to
    end
  end

  def edit
    if params[:token].blank?
      redirect_to new_session_path, alert: "Invalid reset link." and return
    end

    user = User.find_by_token_for(:password_reset, params[:token])

    if user.nil?
      redirect_to new_session_path, alert: "Invalid or expired reset link." and return
    end

    @token = params[:token]
  end

  def update
    if params[:token].blank?
      redirect_to new_session_path, alert: "Invalid reset link." and return
    end

    @user = User.find_by_token_for(:password_reset, params[:token])

    if @user.nil?
      redirect_to new_session_path, alert: "Invalid or expired reset link." and return
    end

    if @user.update(
        password: params[:password],
        password_confirmation: params[:password_confirmation]
    )
      # The token is invalidated automatically: changing the password rotates
      # the bcrypt salt the token is derived from, so it can't be reused.
      redirect_to new_session_path, alert: "Password updated. Please log in."
    else
      @token = params[:token]
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def default_redirect_to
      redirect_to new_session_path, alert: "Check your email for reset instructions."
    end

    def redirect_to_many_req
      redirect_to new_session_path, alert: "Too many password reset requests."
    end
end
