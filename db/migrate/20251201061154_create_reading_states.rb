class CreateReadingStates < ActiveRecord::Migration[8.1]
  def change
    create_table :user_articles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :article, null: false, foreign_key: true
      t.datetime :read_at

      t.timestamps
    end
  end
end
