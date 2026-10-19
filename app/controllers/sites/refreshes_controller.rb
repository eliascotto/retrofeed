class Sites::RefreshesController < ApplicationController
  # POST /sites/:site_id/refresh
  def create
    @website = Website.find(params[:site_id])

    unless current_user.websites.include?(@website)
      respond_to do |format|
        format.html { redirect_to sites_path, alert: "Site not found" }
        format.json { head :not_found }
      end
      return
    end

    if @website.archive_url.blank?
      respond_to do |format|
        format.html { redirect_back fallback_location: site_path(@website), alert: "Website has no archive URL" }
        format.json { head :unprocessable_entity }
      end
      return
    end

    unless WebProcessor.should_crawl_archive?(@website, force: true)
      respond_to do |format|
        format.html do
          time_until_refresh = @website.last_crawled_at + WebProcessor.archive_min_interval - Time.current
          minutes_remaining = (time_until_refresh / 60).ceil
          redirect_back fallback_location: site_path(@website),
                        alert: "Website was recently refreshed. Try again in #{minutes_remaining} minute(s)."
        end
        format.json { head :too_many_requests }
      end
      return
    end

    @website.refresh_later
    respond_to do |format|
      format.html { redirect_back fallback_location: site_path(@website), notice: "Website refresh queued" }
      format.json { head :ok }
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to sites_path, alert: "Site not found" }
      format.json { head :not_found }
    end
  end
end
