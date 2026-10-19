require "rake"

module Admin
  class TaskRunner
    Result = Struct.new(:output, :error, :success, keyword_init: true) do
      def success? = success
    end

    def self.call(task_definition, args)
      Rails.application.load_tasks unless Rake::Task.task_defined?(task_definition.name)
      rake_task = Rake::Task[task_definition.name]
      rake_task.reenable

      captured = StringIO.new
      original_stdout = $stdout
      $stdout = captured

      begin
        rake_task.invoke(*args)
        Result.new(output: captured.string, error: nil, success: true)
      rescue SystemExit, StandardError => e
        Result.new(output: captured.string, error: "#{e.class}: #{e.message}", success: false)
      ensure
        $stdout = original_stdout
      end
    end
  end
end
