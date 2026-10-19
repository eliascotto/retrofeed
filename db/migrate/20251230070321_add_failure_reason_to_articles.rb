class AddFailureReasonToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :failure_reason, :string
  end
end
