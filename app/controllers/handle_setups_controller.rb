class HandleSetupsController < ApplicationController
  layout "minimal"

  # Skip require_handle since this is where users set their handle
  skip_before_action :require_handle

  def new
    # If user already has a handle, redirect to home
    if current_user.handle_setup_complete?
      redirect_to root_path
      nil
    end
  end

  def create
    # If user already has a handle, redirect to home
    if current_user.handle_setup_complete?
      redirect_to root_path
      return
    end

    handle = params[:handle]&.strip

    if handle.blank?
      flash.now[:alert] = "Handle is required"
      render :new, status: :unprocessable_entity
      return
    end

    if User.where.not(id: current_user.id).exists?(handle: handle)
      flash.now[:alert] = "This handle is already taken. Please choose another one."
      render :new, status: :unprocessable_entity
      return
    end

    if current_user.update(handle: handle)
      redirect_to root_path, notice: "Handle set successfully. Welcome to Retrofeed!"
    else
      flash.now[:alert] = current_user.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end
end
