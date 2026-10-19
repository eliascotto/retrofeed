class AddArchiveDetectionFieldsToWebsites < ActiveRecord::Migration[8.1]
  def change
    add_column :websites, :archive_paginated, :boolean, default: false, null: false
    add_column :websites, :archive_detection_method, :string
    add_column :websites, :archive_confidence_score, :float
  end
end
