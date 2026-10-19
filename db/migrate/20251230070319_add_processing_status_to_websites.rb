class AddProcessingStatusToWebsites < ActiveRecord::Migration[8.1]
  def change
    add_column :websites, :processing_status, :string, default: "pending", null: false
    add_column :websites, :processing_started_at, :datetime
    add_column :websites, :processing_error_message, :text
    add_column :websites, :processing_failed_at, :datetime

    add_index :websites, :processing_status
  end
end
