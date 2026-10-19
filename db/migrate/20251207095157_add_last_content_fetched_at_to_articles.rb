class AddLastContentFetchedAtToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :last_content_fetched_at, :datetime
  end
end
