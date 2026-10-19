class Api::Lists::ArticlesController < Api::ListArticlesController
  private

  def list
    @list ||= List.find_by_public_slug_for_user(params[:list_id], current_user)
  end
end
