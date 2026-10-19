class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :website

  # Validation for user uniqueness per website
  validates :user_id, uniqueness: { scope: :website_id }

  scope :for_user, ->(user) { where(user_id: user.id) }

  after_destroy :clean_up_associations

  after_create_commit :broadcast_new_site
  after_destroy_commit :broadcast_removed_site

  def new_articles_since
    last_seen_at || created_at
  end

  def new_articles_count
    website.articles
      .where.not(id: user.user_articles.removed.select(:article_id))
      .where("articles.created_at > ?", new_articles_since)
      .count
  end

  def mark_seen!
    update!(last_seen_at: Time.current)
    progress = website.progress_stats
    total_count = website.articles.with_content.count

    Turbo::StreamsChannel.broadcast_replace_later_to(
      "user_#{user_id}",
      target: "article-count-#{website.id}",
      partial: "sites/article_count",
      locals: { new_count: new_articles_count, website:, user:, progress:, total_count: }
    )
  end

  private
    # Turbo Stream updates for the sites sidebar when a subscription is added.
    # Mirrors `broadcast_removed_site` so the two callbacks stay symmetric.
    def broadcast_new_site
      progress = website.progress_stats
      total_count = website.articles.with_content.count

      Turbo::StreamsChannel.broadcast_prepend_later_to(
        "user_#{user_id}",
        target: "sites-list",
        partial: "sites/site_list_item",
        locals: {
          website:,
          user:,
          new_count: 0, # New website, so no updates
          progress:,
          total_count:
        }
      )

      # Remove empty state if it exists
      Turbo::StreamsChannel.broadcast_remove_to(
        "user_#{user_id}",
        target: "sites-empty-state"
      )

      # Update site counter
      Turbo::StreamsChannel.broadcast_replace_to(
        "user_#{user_id}",
        target: "sites-counter",
        partial: "sites/counter",
        locals: { user: }
      )
    end

    # Turbo Stream updates for the sites sidebar when a subscription is removed.
    # Mirrors `broadcast_new_site`: drop the row, refresh the counter, and
    # re-render the empty state if this was the user's last subscription.
    def broadcast_removed_site
      Turbo::StreamsChannel.broadcast_remove_to(
        "user_#{user_id}",
        target: ActionView::RecordIdentifier.dom_id(website)
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        "user_#{user_id}",
        target: "sites-counter",
        partial: "sites/counter",
        locals: { user: }
      )

      if user.subscriptions.reload.empty?
        Turbo::StreamsChannel.broadcast_append_to(
          "user_#{user_id}",
          target: "sites-list",
          partial: "sites/empty_state"
        )
      end
    end

    def clean_up_associations
      # Remove reading states for articles from this website for this user
      UserArticle.joins(:article)
                  .where(user_id: user_id, articles: { website_id: website_id })
                  .destroy_all

      # Remove article tags where the tag belongs to this user and article belongs to this website
      ArticleTag.joins(:article, :tag)
                .where(tags: { user_id: user_id }, articles: { website_id: website_id })
                .destroy_all
    end
end
