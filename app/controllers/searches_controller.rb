class SearchesController < ApplicationController
  def show
    @query = params[:q]&.strip
    @tab = params[:tab] || "articles"
    @page = params[:page].to_i
    @page = 1 if @page < 1

    if @query.blank?
      @articles = Article.none
      @sites = Website.none
      @articles_total = 0
      @sites_total = 0
      @articles_total_pages = 0
      @sites_total_pages = 0
      return
    end

    # Get visible websites the user is subscribed to (excludes failed ones)
    website_ids = current_user.websites.pluck(:id)

    # Escape special LIKE characters and build search pattern
    escaped_query = escape_like_pattern(@query)
    search_pattern = "%#{escaped_query}%"

    # Get candidate articles using SQL (fast, uses indexes)
    # This narrows down to articles matching title or content_html/content_md
    articles_relation = Article.where(website_id: website_ids)
                          .where(search_articles_conditions, query: search_pattern)
                          .select(:id, :title, :publication_date, :created_at, :website_id, :word_count, :content_html, :content_md)
                          .order(publication_date: :desc, created_at: :desc)

    # Convert to array and filter using content_text (plain text) for accurate matching
    # This ensures we match against stripped HTML, not raw HTML tags
    query_lower = @query.downcase
    candidate_articles = articles_relation.to_a
    filtered_articles = candidate_articles.select do |article|
      title_match = article.title&.downcase&.include?(query_lower)
      content_match = article.content_text.downcase.include?(query_lower)
      title_match || content_match
    end

    # Paginate articles
    per_page = pagination_per_page
    @articles_total = filtered_articles.size
    @articles_total_pages = total_pages(@articles_total, per_page:)
    @articles_page = clamp_page(@articles_total_pages)
    @articles = filtered_articles[offset_for(@articles_page, per_page:), per_page] || []

    # Search sites (name)
    sites_base_scope = Website.where(id: website_ids)
                        .where(search_sites_conditions, query: search_pattern)

    # Paginate sites
    @sites_total = sites_base_scope.count
    @sites_total_pages = total_pages(@sites_total, per_page:)
    @sites_page = clamp_page(@sites_total_pages)

    sites_scope = sites_base_scope.select(:id, :name, :domain)
                                  .order(name: :asc, domain: :asc)
    @sites = sites_scope.limit(per_page).offset(offset_for(@sites_page, per_page:))
  end

  private
    def search_articles_conditions
      # Cross-database compatible case-insensitive search
      # Works with both SQLite and Postgres
      "LOWER(title) LIKE LOWER(:query) OR
      LOWER(content_html) LIKE LOWER(:query) OR
      LOWER(content_md) LIKE LOWER(:query)"
    end

    def search_sites_conditions
      # Cross-database compatible case-insensitive search
      "LOWER(name) LIKE LOWER(:query) OR
      LOWER(domain) LIKE LOWER(:query)"
    end

    def escape_like_pattern(pattern)
      # Escape special LIKE characters: %, _, and \
      # SQLite uses backslash escaping, Postgres uses backslash escaping in some contexts
      # For maximum compatibility, we'll escape these characters
      # Note: In parameterized queries, Rails handles SQL injection, but LIKE wildcards need manual escaping
      pattern.gsub(/[%_\\]/) { |char| "\\#{char}" }
    end

    def total_pages(total_count, per_page:)
      (total_count.to_f / per_page).ceil
    end

    def offset_for(page, per_page:)
      (page - 1) * per_page
    end

    def clamp_page(total_pages)
      return 1 if total_pages.zero?

      [ [ @page, total_pages ].min, 1 ].max
    end
end
