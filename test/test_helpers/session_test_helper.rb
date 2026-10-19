module SessionTestHelper
  def login_as(user, password: "password123")
    # Support user as a symbol
    if !user.is_a?(User)
      user = users(user)
    end

    post sessions_path, params: { email: user.email, password: password }
  end

  def logout(user = nil)
    delete session_path(user&.id || current_user.id)
  end

  private
    def current_user
      User.find_by(id: session[:user_id]) if session[:user_id]
    end
end
