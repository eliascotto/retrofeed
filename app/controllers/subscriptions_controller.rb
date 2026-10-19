class SubscriptionsController < ApplicationController
  def destroy
    website = Website.find(params[:site_id])
    subscription = current_user.subscriptions.find_by(website: website)

    if subscription
      subscription.destroy
      redirect_back fallback_location: sites_path, notice: "Site removed"
    else
      redirect_back fallback_location: sites_path, alert: "Subscription not found"
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to sites_path, alert: "Site not found"
  end
end
