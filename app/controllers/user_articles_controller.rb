class UserArticlesController < ApplicationController
  before_action :set_article

  def mark_read
    record = UserArticle.find_or_create_by(user: current_user, article: @article)
    record.update(read_at: Time.current) if record.read_at.nil?
    head :ok
  end

  def mark_unread
    record = UserArticle.find_by(user: current_user, article: @article)
    record&.update(read_at: nil)   # NOTE: change of behavior — see below
    head :ok
  end

  def remove
    record = UserArticle.find_or_create_by(user: current_user, article: @article)
    record.update(removed_at: Time.current) if record.removed_at.nil?
    redirect_to site_path(@article.website), status: :see_other
  end

  def restore
    record = UserArticle.find_by(user: current_user, article: @article)

    if record.nil?
      flash[:error] = "Cannot restore unsaved article"
      redirect_to site_path(@article.website), status: :see_other
    end

    unless @article.has_content?
      record.destroy
    else
      record.update(removed_at: nil)
    end

    redirect_to site_path(@article.website), status: :ok
  end

  private
    def set_article
      @article = Article.find(params[:article_id])
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
end
