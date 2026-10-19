require "test_helper"

class EmailTrackingServiceTest < ActiveSupport::TestCase
  setup do
    EmailSend.delete_all
  end

  test "increment_daily_count creates a new record for today if none exists" do
    assert_difference -> { EmailSend.count }, 1 do
      EmailTrackingService.increment_daily_count
    end

    record = EmailSend.find_by(date: Date.current)
    assert_not_nil record
    assert_equal 1, record.count
  end

  test "increment_daily_count increments existing record" do
    EmailSend.create!(date: Date.current, count: 5)

    assert_no_difference -> { EmailSend.count } do
      EmailTrackingService.increment_daily_count
    end

    assert_equal 6, EmailSend.find_by(date: Date.current).count
  end

  test "daily_count returns 0 when no record exists" do
    assert_equal 0, EmailTrackingService.daily_count
  end

  test "daily_count returns correct count for today" do
    EmailSend.create!(date: Date.current, count: 42)

    assert_equal 42, EmailTrackingService.daily_count
  end

  test "approaching_limit? returns false when under threshold" do
    EmailSend.create!(date: Date.current, count: 89)

    assert_not EmailTrackingService.approaching_limit?
  end

  test "approaching_limit? returns true at threshold" do
    EmailSend.create!(date: Date.current, count: 90)

    assert EmailTrackingService.approaching_limit?
  end

  test "over_limit? returns false when under limit" do
    EmailSend.create!(date: Date.current, count: 99)

    assert_not EmailTrackingService.over_limit?
  end

  test "over_limit? returns true at limit" do
    EmailSend.create!(date: Date.current, count: 100)

    assert EmailTrackingService.over_limit?
  end

  test "can_send_email? returns true when under limit" do
    EmailSend.create!(date: Date.current, count: 99)

    assert EmailTrackingService.can_send_email?
  end

  test "can_send_email? returns false when over limit" do
    EmailSend.create!(date: Date.current, count: 100)

    assert_not EmailTrackingService.can_send_email?
  end
end
