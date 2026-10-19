class Article < ApplicationRecord
  belongs_to :website

  has_many :user_articles, dependent: :destroy
  has_many :article_tags, dependent: :destroy
  has_many :list_articles, dependent: :destroy
  has_many :article_versions, dependent: :destroy
  has_many :tags, through: :article_tags
  has_many :lists, through: :list_articles

  # Articles with content (html or markdown)
  scope :with_content, -> { where("content_html IS NOT NULL AND content_html != ''
    OR content_md IS NOT NULL AND content_md != ''") }

  after_create_commit :broadcast_new_article_badge
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  enum :status, {
    pending:    "pending",
    crawling:   "crawling",
    extracting: "extracting",
    completed:  "completed",
    failed:     "failed"
  }, default: "pending"

  VALID_TRANSITIONS = {
    "pending"    => %w[crawling extracting failed],
    "crawling"   => %w[extracting failed],
    "extracting" => %w[completed failed],
    "completed"  => %w[pending], # refetch/reset article
    "failed"     => %w[pending crawling]
  }.freeze

  validate :validate_status_transition,
    if: :status_changed?,
    unless: :new_record?

  def validate_status_transition
    from = status_was
    to   = status
    unless VALID_TRANSITIONS.fetch(from, []).include?(to)
      errors.add(:status, "cannot transition from '#{from}' to '#{to}'")
    end
  end

  def read_by?(user)
    user_articles.where(user: user).where.not(read_at: nil).exists?
  end

  def has_content?
    content_html.present? || content_md.present?
  end

  def read_at_for(user)
    user_articles.find_by(user: user)&.read_at
  end

  # Returns plain text content without formatting
  # Prefers markdown, falls back to HTML
  def content_text
    if content_md.present?
      Markdown.to_text(content_md)
    elsif content_html.present?
      ActionController::Base.helpers.strip_tags(content_html)
    else
      ""
    end
  end

  def next_version_number
    (article_versions.maximum(:version) || 0) + 1
  end

  private
    def broadcast_new_article_badge
      website.subscriptions.includes(:user).find_each do |subscription|
        if subscription.last_seen_at.nil? || self.created_at > subscription.last_seen_at
          # TODO
          # broadcasts a replace to `article-count-<website_id>` on `user_<user_id>` channel
          # using a new tiny partial that renders both total count and (if > 0) a "+N new" indicator.
        end
      end
    end

    def broadcast_status_change
      website.subscriptions.includes(:user).find_each do |subscription|
        # We use `renderable:` (ViewComponent integration with Turbo) rather than `partial:`
        # because `ArticleItem` is a component, not a partial.
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_#{subscription.user_id}",
          target: ActionView::RecordIdentifier.dom_id(self),
          renderable: ArticleItem::Component.new(
            current_user: subscription.user,
            article: self,
            is_read: read_by?(subscription.user),
            read_at: read_at_for(subscription.user),
            show_website: false,
            show_favicon: false
          )
        )
      end
    end
end
