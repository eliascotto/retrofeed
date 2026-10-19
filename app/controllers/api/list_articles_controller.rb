class Api::ListArticlesController < ApplicationController
  def create
    list.add_article(Article.find(params[:article_id]))
    render json: { message: "Article added to #{list_name}" }, status: :created
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    list.remove_article(Article.find(params[:article_id]))
    render json: { message: "Article removed from #{list_name}" }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private
    def list
      raise NotImplementedError
    end

    def list_name
      "list"
    end
end
