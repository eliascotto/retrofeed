require "ssrf_filter"

class SitesController < ApplicationController
  def index
    # Show all visible websites the user is subscribed to (excludes failed ones)
    # Preload read and total article counts for each website to avoid N+1 queries
    website_ids = current_user.websites.pluck(:id)

    @read_counts_by_website = current_user.user_articles
                                          .where.not(read_at: nil)
                                          .joins(:article)
                                          .where(articles: { website_id: website_ids })
                                          .group("articles.website_id")
                                          .count
    # Count only articles WITH content (the ones visible to users)
    # Previously counted all articles which was confusing when some were still processing
    @total_counts_by_website = Article.where(website_id: website_ids)
                                     .group(:website_id)
                                     .count

    # Calculate progress data for each website
    @progress_by_website = Website.progress_map(current_user.websites.includes(:articles))

    # for each visible subscription, count articles created after `last_seen_at || created_at`
    @new_counts_by_website = Article
      .joins("INNER JOIN subscriptions ON subscriptions.website_id = articles.website_id")
      .where(subscriptions: { user_id: current_user.id })
      .where("articles.publication_date > COALESCE(subscriptions.last_seen_at, subscriptions.created_at)")
      .where.not(id: current_user.user_articles.removed.select(:article_id))
      .group("articles.website_id")
      .count
  end

  def show
    @website = Website.find(params[:id])

    # Check if user has subscription to this website (must be visible, not failed)
    unless current_user.websites.include?(@website)
      redirect_to error_path(type: "site_no_subscription", site_id: params[:id])
      return
    end

    @sort   = params[:sort].presence_in(%w[date title words]) || "date"
    @order  = params[:order].presence_in(%w[asc desc]) || "desc"
    @filter = params[:filter].presence_in(%w[all saved read removed]) || "all"

    if @filter == "all"
      subscription = current_user.subscriptions.find_by!(website: @website)
      @previous_last_seen = subscription.last_seen_at || subscription.created_at
      subscription.mark_seen!
    end

    # Single query to determine which filter tabs are available
    @filter_saved_count, @filter_read_count, @filter_removed_count =
      current_user.user_articles
        .joins(:article)
        .where(articles: { website_id: @website.id })
        .pick(
          Arel.sql("COUNT(*) FILTER (WHERE removed_at IS NULL)"),
          Arel.sql("COUNT(*) FILTER (WHERE read_at IS NOT NULL AND removed_at IS NULL)"),
          Arel.sql("COUNT(*) FILTER (WHERE removed_at IS NOT NULL)")
        )

    @articles = filtered_articles(@website.articles).order(sort_column => sort_direction)

    # Get progress stats from the website model for accurate processing status
    progress = @website.progress_stats
    @total_articles_count = @articles.count
    @total_articles_with_content_count = @articles.with_content.count
    @has_errors = progress[:has_errors]
    @failed_count = progress[:failed]
    @status = @website.processing_status

    # Preload read article IDs and read_at dates for current user to avoid N+1
    @read_article_ids = current_user.user_articles
                                    .where(article_id: @articles.select(:id))
                                    .where.not(read_at: nil)
                                    .pluck(:article_id)
                                    .to_set
    @read_at_by_article_id = current_user.user_articles
                                         .where(article_id: @articles.select(:id))
                                         .where.not(read_at: nil)
                                         .pluck(:article_id, :read_at)
                                         .to_h

    @read_count = @read_article_ids.count

    # Preload Read Next article IDs
    read_next_list = current_user.read_next_list
    @read_next_article_ids = if read_next_list
      read_next_list.list_articles.pluck(:article_id).to_set
    else
      Set.new
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to error_path(type: "site_not_found")
  end

  # Add a new website
  def create
    url = site_params[:url]

    unless UrlUtils.safe_url_for_processing?(url)
      Rails.logger.info { "DANGEROUS URL submitted by user #{current_user.id}: #{url}" }
      @error_message = "Invalid URL"
      render_error
      return
    end

    @website = current_user.subscribe_to_url(url)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to sites_path, notice: "Site added" }
      format.json { head :created }
    end

  rescue UrlUtils::InvalidUrlError,
        User::AlreadySubscribedError,
        ActiveRecord::RecordInvalid => e
    @error_message = e.message
    render_error
  end

  private
    def render_error(status = :unprocessable_entity)
      respond_to do |format|
        format.turbo_stream { render :create_error, status: status }
        format.html { redirect_to sites_path, alert: @error_message }
        format.json { render :index, status: status }
      end
    end

    def site_params
      params.expect(site: [ :url ])
    end

    def filtered_articles(base)
      case @filter
      when "saved"
        base.joins(:user_articles).where(user_articles: { user_id: current_user.id, removed_at: nil })
      when "read"
        base.joins(:user_articles)
            .where(user_articles: { user_id: current_user.id, removed_at: nil })
            .where.not(user_articles: { read_at: nil })
      when "removed"
        base.joins(:user_articles)
            .where(user_articles: { user_id: current_user.id })
            .where.not(user_articles: { removed_at: nil })
      else
        base.where.not(id: current_user.user_articles.removed.select(:article_id))
      end
    end

    def sort_column
      case @sort
      when "title" then :title
      when "words" then :word_count
      else :publication_date
      end
    end

    def sort_direction
      @order == "asc" ? :asc : :desc
    end
end
