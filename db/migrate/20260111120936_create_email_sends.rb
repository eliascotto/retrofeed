class CreateEmailSends < ActiveRecord::Migration[8.1]
  def change
    create_table :email_sends do |t|
      t.date :date, null: false
      t.integer :count, default: 0, null: false

      t.timestamps
    end
    add_index :email_sends, :date, unique: true
  end
end
