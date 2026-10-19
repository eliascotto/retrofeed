module Admin
  class TasksController < BaseController
    before_action :set_task, only: [ :show, :run ]

    def index
      @tasks_by_group = Admin::TaskDefinition.grouped
    end

    def show
      render partial: "task_details",
        layout: false,
        locals: { task: @task }
    end

    def run
      errors, args = validate_params
      if errors.any?
        @error = errors.join(", ")
        @output = ""
      else
        result = Admin::TaskRunner.call(@task, args)
        @output = result.output
        @error = result.error
      end

      render partial: "output", layout: false
    end

    private
      def set_task
        @task = Admin::TaskDefinition.find(params[:id])
      end

      def validate_params
        raw = params[:task] || {}
        errors = []
        args = []
        @task.params.each do |param|
          error, value = param.validate(raw[param.name])
          if error
            errors << error
          else
            args << value
          end
        end
        [ errors, args ]
      end
  end
end
