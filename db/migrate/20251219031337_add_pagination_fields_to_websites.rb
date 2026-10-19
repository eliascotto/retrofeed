class AddPaginationFieldsToWebsites < ActiveRecord::Migration[8.1]
  def change
    add_column :websites, :pagination_page_limit, :integer
    add_column :websites, :pagination_post_limit, :integer
    add_column :websites, :pagination_last_page_scraped, :integer
    add_column :websites, :pagination_total_pages_found, :integer
    add_column :websites, :pagination_completed_at, :datetime
    add_column :websites, :pagination_halted_reason, :string
  end
end
