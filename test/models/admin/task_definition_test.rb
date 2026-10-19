require "test_helper"

module Admin
  class TaskDefinitionTest < ActiveSupport::TestCase
    test ".all returns the registry" do
      assert Admin::TaskDefinition.all.any?
      assert Admin::TaskDefinition.all.all? { |t| t.title.present? && t.name.present? && t.group.present? }
    end

    test ".find returns the task by id" do
      task = Admin::TaskDefinition.all.first
      assert_equal task, Admin::TaskDefinition.find(task.id)
    end

    test ".find raises for unknown id" do
      assert_raises(ActiveRecord::RecordNotFound) do
        Admin::TaskDefinition.find("nope-not-a-task")
      end
    end

    test ".grouped groups by file group" do
      grouped = Admin::TaskDefinition.grouped
      assert_includes grouped.keys, "admin"
      assert_includes grouped.keys, "articles"
      assert_includes grouped.keys, "users"
      assert_includes grouped.keys, "websites"
    end

    test ".all only surfaces tasks from INCLUDED_FILES" do
      groups = Admin::TaskDefinition.all.map(&:group).uniq
      assert_equal Admin::TaskDefinition::INCLUDED_FILES.sort, groups.sort
    end

    test "documentation is lifted from each rake task's desc comment" do
      task = Admin::TaskDefinition.find("users-list")
      assert_equal "List users", task.documentation
    end

    test "OVERRIDES drives param types and required flags" do
      task = Admin::TaskDefinition.find("users-show")
      assert_equal 1, task.params.length
      assert_equal "id", task.params.first.name
      assert_equal :uuid, task.params.first.type
      assert task.params.first.required
    end

    test "tasks without override fall back to string params derived from arg_names" do
      task = Admin::TaskDefinition.find("websites-refresh_site")
      assert_equal [ "id" ], task.params.map(&:name)
      assert_equal :string, task.params.first.type
    end

    # Regression: in development, Admin::TaskDefinition is reloaded on every
    # request. Re-running Rails.application.load_tasks stacks duplicate action
    # procs onto each rake task, causing the task body to execute N times.
    test "repeated discovery does not duplicate rake task actions" do
      # Force the registry to load by hitting .all
      Admin::TaskDefinition.instance_variable_set(:@all, nil)
      Admin::TaskDefinition.all

      action_count_before = Rake::Task["users:list"].actions.size

      # Simulate a class reload by clearing the memoized registry and asking
      # again — discover() will be invoked again.
      Admin::TaskDefinition.instance_variable_set(:@all, nil)
      Admin::TaskDefinition.all

      action_count_after = Rake::Task["users:list"].actions.size

      assert_equal action_count_before, action_count_after,
        "load_tasks should not be called a second time once lib/tasks is already loaded"
    end

    test "#id is the rake task name with colons replaced" do
      task = Admin::TaskDefinition.new(group: "x", name: "foo:bar_baz", title: "T", documentation: "D")
      assert_equal "foo-bar_baz", task.id
    end

    test ".with_registry swaps and restores" do
      original = Admin::TaskDefinition.all
      replacement = [ Admin::TaskDefinition.new(group: "t", name: "t:fake", title: "Fake", documentation: "") ]

      Admin::TaskDefinition.with_registry(replacement) do
        assert_equal replacement, Admin::TaskDefinition.all
      end

      assert_equal original, Admin::TaskDefinition.all
    end
  end

  class TaskParamTest < ActiveSupport::TestCase
    test "string required and blank returns error" do
      param = Admin::TaskParam.new(name: "domain", type: :string, required: true)
      error, value = param.validate("")
      assert_equal "domain is required", error
      assert_nil value
    end

    test "string required and present returns value" do
      param = Admin::TaskParam.new(name: "domain", type: :string, required: true)
      error, value = param.validate("example.com")
      assert_nil error
      assert_equal "example.com", value
    end

    test "integer with non-numeric value returns error" do
      param = Admin::TaskParam.new(name: "id", type: :integer, required: true)
      error, _ = param.validate("abc")
      assert_equal "id must be an integer", error
    end

    test "integer with numeric value returns value" do
      param = Admin::TaskParam.new(name: "id", type: :integer, required: true)
      error, value = param.validate("42")
      assert_nil error
      assert_equal "42", value
    end

    test "optional blank param returns no error" do
      param = Admin::TaskParam.new(name: "x", type: :string, required: false)
      error, value = param.validate("")
      assert_nil error
      assert_nil value
    end

    test "html_input_type maps to number for integer" do
      assert_equal "number", Admin::TaskParam.new(name: "x", type: :integer).html_input_type
      assert_equal "text", Admin::TaskParam.new(name: "x", type: :string).html_input_type
    end
  end
end
