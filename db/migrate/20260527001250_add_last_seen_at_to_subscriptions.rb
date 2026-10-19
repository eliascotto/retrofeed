class AddLastSeenAtToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # Step 1: Add column
    add_column :subscriptions, :last_seen_at, :datetime

    # Step 2: Backfill existing record
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE subscriptions SET last_seen_at = created_at
          WHERE last_seen_at IS NULL
        SQL
      end
    end
  end
end
