class Api::ReadNext::ListArticlesController < Api::ListArticlesController
  private

  def list
    @list ||= current_user.read_next_list or
      raise ActiveRecord::RecordNotFound, "Read Next list not found"
  end

  def list_name
    "Read Next"
  end
end
