class AddStatusToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :status, :string, default: "pending"
  end
end
