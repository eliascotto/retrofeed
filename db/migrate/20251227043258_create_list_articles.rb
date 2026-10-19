class CreateListArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :list_articles do |t|
      t.references :list, null: false, foreign_key: true
      t.references :article, null: false, foreign_key: true
      t.integer :position

      t.timestamps
    end

    add_index :list_articles, [ :list_id, :article_id ], unique: true
  end
end
