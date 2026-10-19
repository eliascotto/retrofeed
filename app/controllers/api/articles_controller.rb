class Api::ArticlesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :refresh ]
  before_action :set_article, only: [ :mark_read, :mark_unread ]

  # DELETE /api/articles/:id/mark_read
  # Marks an article as unread by removing the UserArticle
  def mark_unread
    user_article = UserArticle.find_by(user: current_user, article: @article)
    user_article&.destroy

    head :ok
  end

  # POST /api/articles/:id/track_view
  #
  # Records that the user actually viewed this article by creating or touching
  # a UserArticle record. This endpoint is called from a Stimulus controller
  # when the article page renders, NOT during Turbo prefetch.
  #
  # Why this exists:
  # Turbo prefetches pages on hover before the user clicks. The prefetch is a
  # real HTTP request, so server-side tracking in the show action would
  # incorrectly record views for articles the user only hovered over. When the
  # user clicks, Turbo serves the cached response without a new request.
  #
  # Solution:
  # The show action no longer tracks views. Instead, a Stimulus controller on
  # the article page calls this endpoint when it connects. Stimulus controllers
  # only connect when the page actually renders (after a click), not during
  # prefetch, so this accurately tracks real views.
  #
  # See: docs/adr_turbo_prefetch_view_tracking.md
  def track_view
    article = Article.find(params[:id])
    user_article = UserArticle.find_or_create_by(user: current_user, article: article)
    user_article.touch

    head :ok
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # POST /api/articles/:id/refresh
  # Request a hard refresh of article content
  def refresh
    article = Article.find(params[:id])

    # Check if refresh is allowed (rate limiting)
    unless WebProcessor.should_update_content?(article, force: true)
      time_until_refresh = article.last_content_fetched_at + WebProcessor.content_min_interval - Time.current
      minutes_remaining = (time_until_refresh / 60).ceil

      render json: {
        error: "Article was recently refreshed",
        retry_after_minutes: minutes_remaining
      }, status: :too_many_requests
      return
    end

    # Enqueue the refresh job with force flag
    job = FetchArticleContentJob.perform_later(article, user_id: nil, force: true)

    render json: {
      job_id: job.job_id,
      status: "pending",
      message: "Article refresh queued"
    }, status: :accepted

  rescue ActiveRecord::RecordNotFound
    render json: { error: "Article not found" }, status: :not_found
  end

  private
      def set_article
        @article = Article.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        head :not_found
      end
end
