class ErrorsController < ApplicationController
  def show
    @error_type = params[:type] || "not_found"
    @error_message = determine_error_message
    @back_path = determine_back_path
  end

  private

  def determine_error_message
    case @error_type
    when "site_not_found"
      "The site you're looking for doesn't exist."
    when "article_not_found"
      "The article you're looking for doesn't exist."
    when "site_no_subscription"
      "You don't have access to this site. Please subscribe to view its content."
    when "article_no_subscription"
      "You don't have access to this article. Please subscribe to the site to view its content."
    else
      "The page you're looking for doesn't exist."
    end
  end

  def determine_back_path
    case @error_type
    when "site_not_found", "site_no_subscription"
      sites_path
    when "article_not_found", "article_no_subscription"
      # Try to get the site_id from params if available
      if params[:site_id].present?
        site_path(params[:site_id])
      else
        sites_path
      end
    else
      root_path
    end
  end
end
