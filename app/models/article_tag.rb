class ArticleTag < ApplicationRecord
  belongs_to :article
  belongs_to :tag

  # Validation for tag uniqueness per article
  validates :tag_id, uniqueness: { scope: :article_id }
end
