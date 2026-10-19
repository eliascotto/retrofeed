class AddUniqueIndexToArticlesUrl < ActiveRecord::Migration[8.1]
  def up
    # First, remove any duplicate articles (keep the most recently updated one)
    execute <<-SQL
      DELETE FROM articles
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM articles
        GROUP BY url
      )
    SQL

    # Remove the existing non-unique index
    remove_index :articles, :url, if_exists: true

    # Add a unique index
    add_index :articles, :url, unique: true
  end

  def down
    remove_index :articles, :url, if_exists: true
    add_index :articles, :url
  end
end
