class AddPublicIdToLists < ActiveRecord::Migration[8.1]
  def change
    add_column :lists, :public_id, :string, limit: 8, null: false
    add_index :lists, :public_id, unique: true
  end
end
