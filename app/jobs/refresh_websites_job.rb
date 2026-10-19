class RefreshWebsitesJob < ApplicationJob
  queue_as :default

  # Recurring job to refresh stale websites
  # This job runs periodically (configured in config/recurring.yml) to:
  # 1. Re-crawl website archives that haven't been crawled within archive_interval
  #
  # This ensures content stays fresh without relying solely on user actions.
  def perform
    Rails.logger.tagged("RefreshWebsitesJob") do
      Rails.logger.debug { "Starting content refresh" }

      refresh_websites

      Rails.logger.debug { "Completed content refresh" }
    end
  end

  private
    def refresh_websites
      stale_threshold = WebProcessor.archive_interval.ago

      stale_websites = Website.where("last_crawled_at < ? OR last_crawled_at IS NULL", stale_threshold)
                              .limit(10) # Process in batches to avoid overwhelming the queue

      Rails.logger.debug { "Found #{stale_websites.count} websites to refresh" }

      stale_websites.each do |website|
        unless website.archive_url.present?
          raise "[RefreshWebsitesJob] Website #{website.id}/#{website.domain} has no archive_url"
        end

        Rails.logger.debug { "Enqueueing archive crawl for: #{website.domain}" }
        ProcessWebsiteJob.perform_later(website.archive_url)
      end
    end
end
