require "test_helper"
require "rake"

module Admin
  class TasksControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = users(:admin)
      @user = users(:test_user)
    end

    # ===== Authentication / authorization =====

    test "index requires authentication" do
      get admin_tasks_path
      assert_redirected_to new_session_path
    end

    test "index forbids non-admin users" do
      login_as(@user)
      get admin_tasks_path
      assert_redirected_to root_path
      assert_equal "Not authorized", flash[:alert]
    end

    test "show forbids non-admin users" do
      login_as(@user)
      get admin_task_path(Admin::TaskDefinition.all.first.id)
      assert_redirected_to root_path
    end

    test "run forbids non-admin users" do
      login_as(@user)
      post run_admin_task_path(Admin::TaskDefinition.all.first.id)
      assert_redirected_to root_path
    end

    # ===== index =====

    test "index renders for admin and groups tasks" do
      login_as(@admin)
      get admin_tasks_path
      assert_response :success
      assert_select "aside section h2", text: "admin"
      assert_select "aside section h2", text: "articles"
      assert_select "a", text: "Job stats"
    end

    # ===== show =====

    test "show renders task details" do
      login_as(@admin)
      task = Admin::TaskDefinition.find("users-show")
      get admin_task_path(task.id)
      assert_response :success
      assert_select "h2", text: task.title
      assert_select "input[name=?]", "task[id]"
      assert_select "button", text: "Run"
    end

    test "show returns 404 for unknown task" do
      login_as(@admin)
      get admin_task_path("does-not-exist")
      assert_response :not_found
    end

    # ===== run =====

    test "run validates required params and does not invoke task" do
      with_fake_registry do |fake_task|
        login_as(@admin)

        invoked = false
        stub_singleton(Admin::TaskRunner, :call, ->(*) { invoked = true; Admin::TaskRunner::Result.new(output: "", error: nil, success: true) }) do
          post run_admin_task_path(fake_task.id), params: { task: { name: "" } }
        end

        assert_response :success
        assert_match "name is required", response.body
        refute invoked, "TaskRunner.call should not be invoked when validation fails"
      end
    end

    test "run validates integer params" do
      with_fake_integer_registry do |fake_task|
        login_as(@admin)
        post run_admin_task_path(fake_task.id), params: { task: { count: "abc" } }
        assert_response :success
        assert_match "count must be an integer", response.body
      end
    end

    test "run executes the rake task and renders captured output" do
      with_fake_registry do |fake_task|
        define_fake_rake_task(fake_task.name) { puts "hello from fake task" }
        login_as(@admin)

        post run_admin_task_path(fake_task.id), params: { task: { name: "world" } }

        assert_response :success
        assert_match "hello from fake task", response.body
      end
    end

    test "run captures errors raised by the rake task" do
      with_fake_registry do |fake_task|
        define_fake_rake_task(fake_task.name) { raise "boom" }
        login_as(@admin)

        post run_admin_task_path(fake_task.id), params: { task: { name: "x" } }

        assert_response :success
        assert_match "RuntimeError: boom", response.body
      end
    end

    test "run can execute the same task twice (reenable)" do
      with_fake_registry do |fake_task|
        count = 0
        define_fake_rake_task(fake_task.name) { count += 1; puts "run number #{count}" }
        login_as(@admin)

        post run_admin_task_path(fake_task.id), params: { task: { name: "x" } }
        assert_match "run number 1", response.body

        post run_admin_task_path(fake_task.id), params: { task: { name: "x" } }
        assert_match "run number 2", response.body
      end
    end

    private
      def with_fake_registry(&block)
        fake = Admin::TaskDefinition.new(
          group: "test",
          name: "admin_test:fake_string",
          title: "Fake string task",
          documentation: "Fake task used in tests",
          params: [ Admin::TaskParam.new(name: "name", type: :string, required: true) ]
        )
        Admin::TaskDefinition.with_registry([ fake ]) do
          yield fake
        end
      end

      def with_fake_integer_registry(&block)
        fake = Admin::TaskDefinition.new(
          group: "test",
          name: "admin_test:fake_int",
          title: "Fake int task",
          documentation: "Fake int task used in tests",
          params: [ Admin::TaskParam.new(name: "count", type: :integer, required: true) ]
        )
        Admin::TaskDefinition.with_registry([ fake ]) do
          yield fake
        end
      end

      def define_fake_rake_task(name, &block)
        Rake::Task[name].clear if Rake::Task.task_defined?(name)
        Rake::Task.define_task(name, &block)
      end
  end
end
