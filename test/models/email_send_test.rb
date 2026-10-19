require "test_helper"

class EmailSendTest < ActiveSupport::TestCase
  test "valid with date and count" do
    email_send = EmailSend.new(date: Date.current + 10.days, count: 25)
    assert email_send.valid?
  end

  test "invalid without date" do
    email_send = EmailSend.new(date: nil, count: 10)
    assert_not email_send.valid?
    assert_includes email_send.errors[:date], "can't be blank"
  end

  test "invalid with duplicate date" do
    existing = email_sends(:today)
    email_send = EmailSend.new(date: existing.date, count: 10)
    assert_not email_send.valid?
    assert_includes email_send.errors[:date], "has already been taken"
  end

  test "invalid with negative count" do
    email_send = EmailSend.new(date: Date.current + 20.days, count: -1)
    assert_not email_send.valid?
    assert_includes email_send.errors[:count], "must be greater than or equal to 0"
  end

  test "valid with zero count" do
    email_send = EmailSend.new(date: Date.current + 30.days, count: 0)
    assert email_send.valid?
  end
end
