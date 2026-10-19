class AddHandleToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :handle, :string

    # Set handle for existing admin user
    User.where(admin: true).update_all(handle: "admin")

    # Make handle not null
    change_column_null :users, :handle, false

    # Add unique index on handle
    add_index :users, :handle, unique: true
  end

  def down
    remove_column :users, :handle
  end
end
