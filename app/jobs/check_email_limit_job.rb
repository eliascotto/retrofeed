class CheckEmailLimitJob < ApplicationJob
  queue_as :default

  def perform
    if EmailTrackingService.over_limit?
      EmailLimitAlertJob.perform_later("over")
    elsif EmailTrackingService.approaching_limit?
      EmailLimitAlertJob.perform_later("approaching")
    end
  end
end
