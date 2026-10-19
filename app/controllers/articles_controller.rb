class ArticlesController < ApplicationController
  layout "minimal"
  before_action :set_article

  def show
    @website = @article.website

    unless current_user.websites.exists?(@website.id)
      redirect_to error_path(type: "article_no_subscription", site_id: @website.id), alert: "You are not subscribed to this site"
    end

    # Note: UserArticle tracking moved to Api::ArticlesController#track_view
    # and triggered via Stimulus controller on page render.
    #
    # This avoids tracking views during Turbo prefetch (hover) since prefetch
    # fetches HTML but doesn't execute JavaScript or mount Stimulus controllers.
    # See: docs/adr_turbo_prefetch_view_tracking.md
  end

  def random
    mark_article_as_read
    next_article = current_user.unread_articles.where.not(id: @article.id).order("RANDOM()").first

    if next_article
      redirect_to article_path(next_article)
    else
      redirect_to site_path(@article.website), notice: "No more unread articles"
    end
  end

  def next
    mark_article_as_read
    next_one = current_user.unread_articles_for_website(@article.website)
                           .where.not(id: @article.id)
                           .first

    if next_one
      redirect_to article_path(next_one)
    else
      redirect_to site_path(@article.website), notice: "No more unread articles from this site"
    end
  end

  private
    def set_article
      @article = Article.find_by(id: params[:id])
      unless @article
        redirect_to error_path(type: "article_not_found") and return
      end
    end

    def mark_article_as_read
      user_article = UserArticle.find_or_create_by(user: current_user, article: @article)
      user_article.update(read_at: Time.current) if user_article.read_at.nil?
    end
end
