class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  include EnvironmentAware
  include SetPlatform

  # CSRF protection
  protect_from_forgery with: :exception

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login
  before_action :require_handle
  before_action :set_pagination_per_page

  private

  # Require the user to be logged in
  def require_login
    unless current_user
      redirect_to new_session_path, alert: "Please log in to continue"
    end
  end

  # Require the user to have a handle set
  def require_handle
    return unless current_user

    unless current_user.handle_setup_complete?
      redirect_to new_handle_setup_path, alert: "Please choose a handle to continue"
    end
  end

  # Set the pagination per page from the request parameters
  def set_pagination_per_page
    return unless params[:per_page].present?

    per_page = params[:per_page].to_i
    allowed_values = [ 10, 20, 50, 100 ]
    session[:per_page] = allowed_values.include?(per_page) ? per_page : 20
  end

  # Get the pagination per page from the session
  def pagination_per_page
    (session[:per_page] || 20).to_i
  end

  # Get the current user from the session
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # Check if the request is a prefetch request
  def prefetch_request?
    request.headers["Purpose"] == "prefetch" ||
    request.headers["Sec-Purpose"] == "prefetch" ||
    request.headers["x-sec-purpose"] == "prefetch"
  end

  helper_method :current_user, :pagination_per_page
end
