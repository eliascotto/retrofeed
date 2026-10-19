class CreateBlogs < ActiveRecord::Migration[8.1]
  def change
    create_table :blogs do |t|
      t.string :name
      t.string :base_url
      t.string :archive_url
      t.datetime :last_crawled_at

      t.timestamps
    end
  end
end
