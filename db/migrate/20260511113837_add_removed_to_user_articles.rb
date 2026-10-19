class AddRemovedToUserArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :user_articles, :removed_at, :datetime
  end
end
