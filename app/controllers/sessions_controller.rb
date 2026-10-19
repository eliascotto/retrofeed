class SessionsController < ApplicationController
  layout "minimal"

  skip_before_action :require_login, only: [ :new, :create ]
  skip_before_action :require_handle, only: [ :new, :create ]

  rate_limit to: 10, within: 1.minute, only: :create, with: :rate_limit_exceeded

  def new
    # Clear the "Please log in to continue" alert since it's redundant on the login page
    flash[:alert] = nil if flash[:alert] == "Please log in to continue"
  end

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      unless user.email_confirmed?
        session[:unconfirmed_user_id] = user.id
        redirect_to new_confirmation_path, alert: "Please confirm your email address to continue"
        return
      end

      session[:user_id] = user.id

      # Redirect to handle setup if user hasn't set a handle yet
      if user.handle_setup_complete?
        redirect_to root_path, notice: "Logged in successfully"
      else
        redirect_to new_handle_setup_path, notice: "Logged in successfully"
      end
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:user_id] = nil
    session[:unconfirmed_user_id] = nil
    redirect_to new_session_path, notice: "Logged out successfully"
  end

  private
    def rate_limit_exceeded
      redirect_to new_session_path, alert: "Too many login attempts. Please try again later."
    end
end
