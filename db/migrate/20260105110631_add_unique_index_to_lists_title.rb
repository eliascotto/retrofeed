class AddUniqueIndexToListsTitle < ActiveRecord::Migration[8.1]
  def up
    # Remove any duplicate titles per user (keep the most recently updated one)
    execute <<-SQL
      DELETE FROM lists
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM lists
        GROUP BY user_id, title
      )
    SQL

    # Add unique index on user_id and title
    add_index :lists, [ :user_id, :title ], unique: true
  end

  def down
    remove_index :lists, [ :user_id, :title ], if_exists: true
  end
end
