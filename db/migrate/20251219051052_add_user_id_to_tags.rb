class AddUserIdToTags < ActiveRecord::Migration[8.1]
  def change
    add_reference :tags, :user, null: false, foreign_key: true
    add_index :tags, [ :user_id, :name ], unique: true
  end
end
