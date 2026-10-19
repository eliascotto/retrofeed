class ArticleVersion < ApplicationRecord
  belongs_to :article

  validates :version, presence: true,
    uniqueness: { scope: :article_id }
  validates :content_hash, presence: true

  scope :latest_first, -> { order(version: :desc) }
end
