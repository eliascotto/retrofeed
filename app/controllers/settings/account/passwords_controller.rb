class Settings::Account::PasswordsController < ApplicationController
  def show
    @user = current_user
  end

  def update
    @user = current_user
    current_password = params[:current_password]

    if current_password.blank?
      @user.errors.add(:current_password, "is required to change your password")
      render :show, status: :unprocessable_entity
      return
    end

    unless @user.authenticate(current_password)
      @user.errors.add(:current_password, "is incorrect")
      render :show, status: :unprocessable_entity
      return
    end

    if @user.update(password_params)
      redirect_to settings_account_path, notice: "Password updated successfully"
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def password_params
      params.require(:user).permit(:password, :password_confirmation)
    end
end
