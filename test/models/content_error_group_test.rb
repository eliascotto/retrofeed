require "test_helper"

class ContentErrorGroupTest < ActiveSupport::TestCase
  setup do
    @website = websites(:one)
    @article = articles(:one)
    @valid_attributes = {
      fingerprint: "abc123",
      phase: "fetch",
      operation: "article_html_fetch",
      message: "HTTP 500 error",
      severity: "error",
      status: "open",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    }
  end

  # ===== Validation tests =====

  test "valid with all required attributes" do
    error_group = ContentErrorGroup.new(@valid_attributes)
    assert error_group.valid?
  end

  test "fingerprint is required" do
    error_group = ContentErrorGroup.new(@valid_attributes.except(:fingerprint))
    assert_not error_group.valid?
    assert_includes error_group.errors[:fingerprint], "can't be blank"
  end

  test "phase is required" do
    error_group = ContentErrorGroup.new(@valid_attributes.except(:phase))
    assert_not error_group.valid?
    assert_includes error_group.errors[:phase], "can't be blank"
  end

  test "operation is required" do
    error_group = ContentErrorGroup.new(@valid_attributes.except(:operation))
    assert_not error_group.valid?
    assert_includes error_group.errors[:operation], "can't be blank"
  end

  test "message is required" do
    error_group = ContentErrorGroup.new(@valid_attributes.except(:message))
    assert_not error_group.valid?
    assert_includes error_group.errors[:message], "can't be blank"
  end

  test "first_seen_at is required" do
    error_group = ContentErrorGroup.new(@valid_attributes.except(:first_seen_at))
    assert_not error_group.valid?
    assert_includes error_group.errors[:first_seen_at], "can't be blank"
  end

  test "last_seen_at is required" do
    error_group = ContentErrorGroup.new(@valid_attributes.except(:last_seen_at))
    assert_not error_group.valid?
    assert_includes error_group.errors[:last_seen_at], "can't be blank"
  end

  # ===== Status validation tests =====

  test "status must be in allowed values" do
    ContentErrorGroup::STATUSES.each do |status|
      error_group = ContentErrorGroup.new(@valid_attributes.merge(status: status))
      assert error_group.valid?, "Expected status '#{status}' to be valid"
    end
  end

  test "status cannot be invalid value" do
    error_group = ContentErrorGroup.new(@valid_attributes.merge(status: "invalid"))
    assert_not error_group.valid?
    assert_includes error_group.errors[:status], "is not included in the list"
  end

  test "allowed statuses are open, resolved, ignored" do
    assert_equal %w[open resolved ignored], ContentErrorGroup::STATUSES
  end

  # ===== Severity validation tests =====

  test "severity must be in allowed values" do
    ContentErrorGroup::SEVERITIES.each do |severity|
      error_group = ContentErrorGroup.new(@valid_attributes.merge(severity: severity))
      assert error_group.valid?, "Expected severity '#{severity}' to be valid"
    end
  end

  test "severity cannot be invalid value" do
    error_group = ContentErrorGroup.new(@valid_attributes.merge(severity: "critical"))
    assert_not error_group.valid?
    assert_includes error_group.errors[:severity], "is not included in the list"
  end

  test "allowed severities are warn and error" do
    assert_equal %w[warn error], ContentErrorGroup::SEVERITIES
  end

  # ===== Polymorphic association tests =====

  test "can belong to a website" do
    error_group = ContentErrorGroup.create!(@valid_attributes.merge(
      subject: @website
    ))

    assert_equal @website, error_group.subject
    assert_equal "Website", error_group.subject_type
    assert_equal @website.id, error_group.subject_id
  end

  test "can belong to an article" do
    error_group = ContentErrorGroup.create!(@valid_attributes.merge(
      subject: @article
    ))

    assert_equal @article, error_group.subject
    assert_equal "Article", error_group.subject_type
    assert_equal @article.id, error_group.subject_id
  end

  test "subject is optional" do
    error_group = ContentErrorGroup.new(@valid_attributes.merge(
      subject: nil
    ))

    assert error_group.valid?
    assert_nil error_group.subject
  end

  # ===== Fingerprint tests =====

  test "fingerprint can be used for deduplication" do
    fingerprint = "unique-fingerprint-123"

    error_group1 = ContentErrorGroup.create!(@valid_attributes.merge(fingerprint: fingerprint))

    # Can find by fingerprint
    found = ContentErrorGroup.find_by(fingerprint: fingerprint)
    assert_equal error_group1, found
  end

  test "multiple error groups can have same fingerprint" do
    fingerprint = "duplicate-fingerprint"

    error_group1 = ContentErrorGroup.create!(@valid_attributes.merge(fingerprint: fingerprint))
    error_group2 = ContentErrorGroup.create!(@valid_attributes.merge(fingerprint: fingerprint))

    # Both should exist
    assert ContentErrorGroup.where(fingerprint: fingerprint).count == 2
  end

  # ===== Timestamp tests =====

  test "last_seen_at can be updated" do
    error_group = ContentErrorGroup.create!(@valid_attributes)
    original_last_seen = error_group.last_seen_at

    new_time = Time.current + 1.hour
    error_group.update!(last_seen_at: new_time)

    assert error_group.last_seen_at > original_last_seen
  end

  test "first_seen_at should remain constant" do
    error_group = ContentErrorGroup.create!(@valid_attributes)
    original_first_seen = error_group.first_seen_at

    error_group.update!(last_seen_at: Time.current + 1.hour)

    # first_seen_at should not change
    assert_equal original_first_seen.to_i, error_group.reload.first_seen_at.to_i
  end

  # ===== Status transition tests =====

  test "can transition from open to resolved" do
    error_group = ContentErrorGroup.create!(@valid_attributes.merge(status: "open"))

    error_group.update!(status: "resolved")

    assert_equal "resolved", error_group.status
  end

  test "can transition from open to ignored" do
    error_group = ContentErrorGroup.create!(@valid_attributes.merge(status: "open"))

    error_group.update!(status: "ignored")

    assert_equal "ignored", error_group.status
  end

  test "can transition from resolved back to open" do
    error_group = ContentErrorGroup.create!(@valid_attributes.merge(status: "resolved"))

    error_group.update!(status: "open")

    assert_equal "open", error_group.status
  end
end
