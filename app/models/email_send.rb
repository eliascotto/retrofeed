class EmailSend < ApplicationRecord
  validates :date, presence: true, uniqueness: true
  validates :count, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
