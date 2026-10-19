class MakeHandleNullableInUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :handle, true
  end
end
