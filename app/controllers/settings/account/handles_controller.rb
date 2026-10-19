class Settings::Account::HandlesController < ApplicationController
  def show
    @user = current_user
  end

  def update
    @user = current_user

    if @user.update(handle_params)
      redirect_to settings_account_path, notice: "Handle updated successfully"
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def handle_params
    params.require(:user).permit(:handle)
  end
end
