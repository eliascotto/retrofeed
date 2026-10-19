class ListArticle < ApplicationRecord
  belongs_to :list
  belongs_to :article

  # Validation for article uniqueness per list
  validates :article_id, uniqueness: { scope: :list_id }

  # Default ordering by position
  default_scope { order(:position) }
end
