class AddUniqueIndexToSubscriptionsAndUserArticles < ActiveRecord::Migration[8.1]
  def up
    # Remove any duplicate subscriptions before adding the constraint,
    # keeping the oldest record in each duplicate group.
    execute <<~SQL
      DELETE FROM subscriptions
      WHERE id NOT IN (
        SELECT DISTINCT ON (user_id, website_id) id
        FROM subscriptions
        ORDER BY user_id, website_id, created_at ASC
      )
    SQL

    add_index :subscriptions, [:user_id, :website_id], unique: true,
              name: "index_subscriptions_on_user_id_and_website_id"

    # Same for user_articles.
    execute <<~SQL
      DELETE FROM user_articles
      WHERE id NOT IN (
        SELECT DISTINCT ON (user_id, article_id) id
        FROM user_articles
        ORDER BY user_id, article_id, created_at ASC
      )
    SQL

    add_index :user_articles, [:user_id, :article_id], unique: true,
              name: "index_user_articles_on_user_id_and_article_id"
  end

  def down
    remove_index :subscriptions, name: "index_subscriptions_on_user_id_and_website_id"
    remove_index :user_articles, name: "index_user_articles_on_user_id_and_article_id"
  end
end
