class ListsController < ApplicationController
  def index
    @sort = params[:sort].presence_in(%w[date title count]) || "date"
    @order = params[:order].presence_in(%w[asc desc]) || "desc"

    @lists = current_user.lists.user_lists

    case @sort
    when "date"
      @lists = @lists.order(updated_at: @order.to_sym)
    when "title"
      @lists = @lists.order(title: @order.to_sym)
    when "count"
      @lists = @lists.left_joins(:list_articles)
                     .group(:id)
                     .order(Arel.sql("COUNT(list_articles.id) #{@order.upcase}"))
    end
  end

  def show
    @list = List.find_by_public_slug_for_user(params[:public_slug], current_user)

    # Check if this is the Read Next list
    @is_read_next_list = @list.slug == List::READ_NEXT_SLUG

    # Get articles in this list with their position, ordered by position
    @list_articles = @list.list_articles.includes(article: :website)

    # Preload read article IDs for current user to avoid N+1
    article_ids = @list_articles.map(&:article_id)
    @read_article_ids = current_user.user_articles
                                    .where(article_id: article_ids)
                                    .where.not(read_at: nil)
                                    .pluck(:article_id)
                                    .to_set
  rescue ActiveRecord::RecordNotFound
    redirect_to error_path(type: "list_not_found")
  end

  def create
    list = current_user.lists.build(list_params)

    if list.save
      redirect_to list_path(list)
    else
      flash[:error] = list.errors.full_messages.first
      redirect_to lists_path, status: :see_other
    end
  end

  def update
    list = List.find_by_public_slug_for_user(params[:id], current_user)

    if list.nil?
      flash[:error] = "List not found"
      redirect_to list_path, status: :see_other and return
    end

    if list.system_list?
      flash[:error] = "System lists cannot be updated"
      redirect_to list_path, status: :see_other and return
    end

    if list.update(list_params)
      flash[:success] = "Updated \"#{list.title}\""
    else
      flash[:error] = list.errors.full_messages.first
    end
    redirect_to lists_path, status: :see_other
  end

  def destroy
    list = List.find_by_public_slug_for_user(params[:id], current_user)

    if list.nil?
      flash[:error] = "List not found"
      redirect_to list_path, status: :see_other
    end

    if list.system_list?
      flash[:error] = "System lists cannot be deleted"
      redirect_to list_path
    end

    list.destroy!
    redirect_to list_path, status: :see_other
  rescue ActiveRecord::RecordNotDestroyed => e
    flash[:error] = e.message
    redirect_to list_path
  end

  private
    def list_params
      params.require(:list).permit(:title, :description, :cover_image)
    end
end
