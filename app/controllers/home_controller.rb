class HomeController < ApplicationController
  def index
    @tab = determine_tab
    @page = [ params[:page].to_i, 1 ].max

    # Save tab preference if user explicitly selected a tab
    if params[:tab].present? && params[:tab] != current_user.home_tab_preference
      current_user.update_home_tab_preference(@tab)
    end

    # Load articles based on selected tab
    if @tab == "reading"
      load_reading_articles
    else
      load_recent_articles
    end
  end

  private
    def determine_tab
      tab = params[:tab].presence || current_user.home_tab_preference
      User::VALID_HOME_TABS.include?(tab) ? tab : User::DEFAULT_HOME_TAB
    end

    def load_recent_articles
      # Articles from subscribed websites that are unread (no user_article or read_at is nil)
      # and that have content_html or content_md
      base_scope = current_user.unread_articles
                              .with_content
                              .order(publication_date: :desc, created_at: :desc)

      paginate_articles(base_scope)
    end

    def load_reading_articles
      # Articles that have been opened but not finished (have user_article with read_at nil)
      base_scope = current_user.reading_articles

      paginate_articles(base_scope)
    end

    def paginate_articles(scope)
      per_page = pagination_per_page
      @total_count = scope.count
      @total_pages = (@total_count.to_f / per_page).ceil
      @page = [ [ @page, @total_pages ].min, 1 ].max if @total_pages > 0

      offset = (@page - 1) * per_page
      @articles = scope.limit(per_page).offset(offset)

      # Preload Read Next article IDs
      read_next_list = current_user.read_next_list
      @read_next_article_ids = if read_next_list
        read_next_list.list_articles.pluck(:article_id).to_set
      else
        Set.new
      end
    end
end
