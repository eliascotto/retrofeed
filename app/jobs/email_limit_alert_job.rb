class EmailLimitAlertJob < ApplicationJob
  queue_as :default

  def perform(status)
    cache_key = "email_limit_alert_sent:#{Date.current}:#{status}"

    return if Rails.cache.exist?(cache_key)

    count = EmailTrackingService.daily_count
    admins = User.admins

    admins.find_each do |admin|
      UserMailer.email_limit_alert(admin, count, status).deliver_now
    end

    Rails.cache.write(cache_key, true, expires_in: 24.hours)
  end
end
