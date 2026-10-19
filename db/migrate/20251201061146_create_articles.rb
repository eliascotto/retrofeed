class CreateArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :articles do |t|
      t.references :blog, null: false, foreign_key: true
      t.string :title
      t.string :url
      t.text :content_html
      t.date :publication_date
      t.string :raw_published_at
      t.string :slug

      t.timestamps
    end
    add_index :articles, :url
  end
end
