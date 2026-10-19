require "rake"

module Admin
  class TaskDefinition
    # Only rake files in lib/tasks/<basename>.rake whose basename is in this list
    # are surfaced on the admin tasks page.
    INCLUDED_FILES = %w[admin users articles websites].freeze

    # Per-task overrides. Keyed by rake task name. Each override may set:
    #   :title         — custom display title (otherwise derived from task name)
    #   :params        — array of hashes: { name:, type:, required: } passed to TaskParam.new
    #
    # If a param hash is omitted for an arg present in `arg_names`, that arg
    # defaults to { type: :string, required: true }.
    OVERRIDES = {
      "articles:list" => {
        params: [
          { name: "website_id", type: :uuid, required: true }
        ]
      },
      "articles:remove" => {
        params: [
          { name: "article_id", type: :uuid, required: true }
        ]
      },
      "articles:reset" => {
        params: [
          { name: "article_id", type: :uuid, required: true }
        ]
      },
      "articles:set_pending" => {
        params: [
          { name: "article_id", type: :uuid, required: true }
        ]
      },
      "users:show" => {
        params: [
          { name: "id", type: :uuid, required: true }
        ]
      },
      "websites:show" => {
        params: [
          { name: "id", type: :uuid, required: true }
        ]
      },
      "websites:remove" => {
        params: [
          { name: "site_id", type: :uuid, required: true }
        ]
      },
      "websites:fresh_site" => {
        params: [
          { name: "site_id", type: :uuid, required: true }
        ]
      },
      "websites:remove_sub" => {
        params: [
          { name: "user_id", type: :uuid, required: true },
          { name: "site_id", type: :uuid, required: true }
        ]
      }
    }.freeze

    attr_reader :group, :name, :title, :documentation, :params

    def initialize(group:, name:, title:, documentation:, params: [])
      @group = group
      @name = name
      @title = title
      @documentation = documentation
      @params = params
    end

    def id
      name.tr(":", "-")
    end

    class << self
      def all
        @all ||= discover.freeze
      end

      def find(id)
        all.find { |task| task.id == id } || raise(ActiveRecord::RecordNotFound, "No admin task with id=#{id}")
      end

      def grouped
        all.group_by(&:group)
      end

      # Test-only escape hatch.
      def with_registry(definitions)
        previous = @all
        @all = definitions.freeze
        yield
      ensure
        @all = previous
      end

      private
        def discover
          # Tell Rake to keep `desc` comments and source locations attached to
          # tasks. Without this, `task.comment` is nil because rake only records
          # metadata when invoked via the CLI with --tasks / --describe.
          Rake::TaskManager.record_task_metadata = true

          tasks_dir = Rails.root.join("lib/tasks").to_s
          load_app_rake_tasks_once(tasks_dir)

          Rake.application.tasks.filter_map do |rake_task|
            source_file = rake_task.actions.first&.source_location&.first
            next unless source_file&.start_with?(tasks_dir)

            group = File.basename(source_file, ".rake")
            next unless INCLUDED_FILES.include?(group)

            build_definition(rake_task, group)
          end.sort_by { |t| [ t.group, t.name ] }
        end

        # `Rake.application` lives in the Rake gem and is NOT reloaded by Rails
        # in development, but `Admin::TaskDefinition` IS reloaded on every
        # request — so any class-level @loaded flag here gets reset. We must
        # check Rake's own state to know whether lib/tasks has already been
        # loaded. Re-running load_tasks stacks duplicate action procs onto
        # each task, causing N copies of the task body to execute per Run.
        def load_app_rake_tasks_once(tasks_dir)
          already_loaded = Rake.application.tasks.any? do |t|
            t.actions.first&.source_location&.first&.start_with?(tasks_dir)
          end
          Rails.application.load_tasks unless already_loaded
        end

        def build_definition(rake_task, group)
          override = OVERRIDES[rake_task.name] || {}
          documentation = rake_task.full_comment.presence || rake_task.comment.to_s
          title = override[:title] || rake_task.name.split(":").last.tr("_", " ").capitalize
          params = build_params(rake_task, override[:params])

          new(group: group, name: rake_task.name, title: title, documentation: documentation, params: params)
        end

        # Build params from the override (if given) otherwise fall back to
        # arg_names with sensible defaults.
        def build_params(rake_task, override_params)
          if override_params
            override_params.map { |attrs| TaskParam.new(**attrs) }
          else
            rake_task.arg_names.map { |arg| TaskParam.new(name: arg.to_s, type: :string, required: true) }
          end
        end
    end
  end
end
