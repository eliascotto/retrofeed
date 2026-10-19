class UserArticle < ApplicationRecord
  belongs_to :user
  belongs_to :article

  validates :user_id, uniqueness: { scope: :article_id }

  scope :read, -> { where.not(read_at: nil) }
  scope :visible, -> { where(removed_at: nil) }
  scope :removed, -> { where.not(removed_at: nil) }
end
