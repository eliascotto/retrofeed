class AddTitleSuffixPatternToWebsites < ActiveRecord::Migration[8.1]
  def change
    add_column :websites, :title_suffix_pattern, :string
  end
end
