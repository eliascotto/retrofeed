class Tag < ApplicationRecord
  belongs_to :user

  # Delete all article tags when the tag is deleted
  has_many :article_tags, dependent: :destroy
  # Get all articles through the article tags
  has_many :articles, through: :article_tags

  # Validation for name uniqueness per user and presence (not null)
  validates :name, presence: true, uniqueness: { scope: :user_id }

  # Validation for name length
  validates :name, length: { maximum: 50 }
end
