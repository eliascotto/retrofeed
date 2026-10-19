class CreateArticleVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :article_versions do |t|
      t.references :article, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :title
      t.text :content_html
      t.text :content_md
      t.string :content_hash, null: false
      t.integer :word_count
      t.date :publication_date

      t.datetime :created_at, null: false
    end

    add_index :article_versions, [ :article_id, :version ], unique: true
  end
end
