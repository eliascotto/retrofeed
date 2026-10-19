class RenameBlogsToWebsites < ActiveRecord::Migration[8.1]
  def up
    # Remove foreign key constraints before renaming
    remove_foreign_key :articles, :blogs if foreign_key_exists?(:articles, :blogs)
    remove_foreign_key :subscriptions, :blogs if foreign_key_exists?(:subscriptions, :blogs)

    # Rename foreign key columns first (before renaming the table)
    rename_column :articles, :blog_id, :website_id
    rename_column :subscriptions, :blog_id, :website_id

    # Rename indexes
    rename_index :articles, :index_articles_on_blog_id, :index_articles_on_website_id if index_exists?(:articles, :blog_id)
    rename_index :subscriptions, :index_subscriptions_on_blog_id, :index_subscriptions_on_website_id if index_exists?(:subscriptions, :blog_id)

    # Rename the table
    rename_table :blogs, :websites

    # Rename column base_url to domain
    rename_column :websites, :base_url, :domain

    # Set default value for any NULL domain values (use archive_url or a placeholder)
    execute <<-SQL
      UPDATE websites#{' '}
      SET domain = COALESCE(archive_url, 'unknown-domain.com')
      WHERE domain IS NULL
    SQL

    # Make domain not nullable
    change_column_null :websites, :domain, false

    # Re-add foreign key constraints with new table name
    add_foreign_key :articles, :websites
    add_foreign_key :subscriptions, :websites
  end

  def down
    # Reverse the foreign key constraints
    remove_foreign_key :articles, :websites
    remove_foreign_key :subscriptions, :websites
    add_foreign_key :articles, :blogs
    add_foreign_key :subscriptions, :blogs

    # Make domain nullable again
    change_column_null :websites, :domain, true

    # Rename column domain back to base_url
    rename_column :websites, :domain, :base_url

    # Rename the table back
    rename_table :websites, :blogs

    # Rename indexes back
    rename_index :articles, :index_articles_on_website_id, :index_articles_on_blog_id
    rename_index :subscriptions, :index_subscriptions_on_website_id, :index_subscriptions_on_blog_id

    # Rename foreign key columns back
    rename_column :articles, :website_id, :blog_id
    rename_column :subscriptions, :website_id, :blog_id
  end
end
