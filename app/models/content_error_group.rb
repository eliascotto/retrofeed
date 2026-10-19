class ContentErrorGroup < ApplicationRecord
  belongs_to :subject, polymorphic: true, optional: true

  STATUSES = %w[open resolved ignored].freeze
  SEVERITIES = %w[warn error].freeze

  validates :fingerprint, :phase, :operation, :message, :first_seen_at, :last_seen_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }
end
