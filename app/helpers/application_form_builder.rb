class ApplicationFormBuilder < ActionView::Helpers::FormBuilder
  def url_field(method, options = {})
    @template.tag.div(class: "form-control") do
      super(method, options.reverse_merge(class: "input input-bordered w-full")) +
      error_for(method)
    end
  end

  private
    def error_for(method)
      return unless object.is_a?(ActiveModel::Validations) && object.errors[method].any?
      @template.tag.p(object.errors[method].first, class: "text-error text-sm")
    end
end
