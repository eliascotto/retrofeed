class AddContentHashToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :content_hash, :string
    add_index :articles, :content_hash
  end
end
