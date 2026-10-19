class AddFullnameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :fullname, :string
  end
end
