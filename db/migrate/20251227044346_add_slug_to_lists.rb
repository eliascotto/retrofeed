class AddSlugToLists < ActiveRecord::Migration[8.1]
  def change
    add_column :lists, :slug, :string
    add_index :lists, [ :user_id, :slug ], unique: true, where: "slug IS NOT NULL"

    # Create Read Next list for all existing users
    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO lists (user_id, title, description, public, slug, created_at, updated_at)
          SELECT id, 'Read Next', 'Articles you want to read later', FALSE, 'read-next', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM users
        SQL
      end
    end
  end
end
