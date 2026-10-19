class AddArticleContentFetchFailedAt < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :content_fetch_failed_at, :datetime
    add_index :articles, :content_fetch_failed_at
  end
end
