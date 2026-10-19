module EmailRateLimiting
  def deliver_tracked(log_context)
    unless EmailTrackingService.can_send_email?
      Rails.logger.warn("Email limit reached, skipping #{log_context}")
      return
    end

    yield

    EmailTrackingService.increment_daily_count
    check_email_limits
  end

  private
    def check_email_limits
      if EmailTrackingService.over_limit?
        EmailLimitAlertJob.perform_later("over")
      elsif EmailTrackingService.approaching_limit?
        EmailLimitAlertJob.perform_later("approaching")
      end
    end
end
