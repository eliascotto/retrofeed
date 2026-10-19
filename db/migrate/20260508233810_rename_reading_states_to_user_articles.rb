class RenameReadingStatesToUserArticles < ActiveRecord::Migration[8.1]
  def change
    rename_table :user_articles, :user_articles
  end
end
