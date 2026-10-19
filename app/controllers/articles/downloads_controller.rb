class Articles::DownloadsController < ApplicationController
  def create
    article = Article.find(params[:article_id])

    # Check if user has subscribed to this website, and connect the article to the user
    unless Subscription.exists?(user_id: current_user.id, website_id: article.website_id)
      return head :forbidden
    end
    UserArticle.find_or_create_by(user: current_user, article: article)

    # Avoid duplicate downloads
    unless article.status.in?([ "pending", "completed", "failed" ])
      return head :ok
    end

    # Check if refresh is allowed (rate limiting)
    if WebProcessor.should_update_content?(article, force: true)
      Rails.logger.debug { "Downloading article #{article.id}" }
      article.update!(status: "crawling")
      # Enqueue the refresh job with force flag
      FetchArticleContentJob.perform_later(article, user_id: nil, force: true)
    end

    head :ok
  rescue ActiveRecord::RecordNotFound
    # Article not found, return a flash message
    head :not_found
  end
end
