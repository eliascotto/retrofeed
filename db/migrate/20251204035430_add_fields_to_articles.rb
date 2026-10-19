class AddFieldsToArticles < ActiveRecord::Migration[8.1]
  def change
    change_column_null :articles, :url, false
    add_column :articles, :word_count, :integer
    add_column :articles, :content_md, :text
  end
end
