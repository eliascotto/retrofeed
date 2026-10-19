class EmailTrackingService
  DAILY_LIMIT = 100
  WARNING_THRESHOLD = 90

  class << self
    def increment_daily_count
      EmailSend.upsert(
        { date: Date.current, count: 1 },
        on_duplicate: Arel.sql("count = email_sends.count + 1"),
        unique_by: :date
      )

      daily_count
    end

    def daily_count
      EmailSend.where(date: Date.current).pick(:count) || 0
    end

    def approaching_limit?
      daily_count >= WARNING_THRESHOLD
    end

    def over_limit?
      daily_count >= DAILY_LIMIT
    end

    def can_send_email?
      !over_limit?
    end
  end
end
