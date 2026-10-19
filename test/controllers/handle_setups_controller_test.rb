require "test_helper"

class HandleSetupsControllerTest < ActionDispatch::IntegrationTest
  # new action - requires login
  test "new requires login" do
    get new_handle_setup_path

    assert_redirected_to new_session_path
  end

  test "new renders handle setup form for user without handle" do
    user = users(:user_without_handle)
    login_as(user)

    get new_handle_setup_path

    assert_response :success
    assert_select "h1", "Choose Your Handle"
  end

  test "new redirects to root for user with handle" do
    user = users(:test_user)
    login_as(user)

    get new_handle_setup_path

    assert_redirected_to root_path
  end

  # create action - requires login
  test "create requires login" do
    post handle_setups_path, params: { handle: "newhandle" }

    assert_redirected_to new_session_path
  end

  test "create redirects to root for user with handle" do
    user = users(:test_user)
    login_as(user)

    post handle_setups_path, params: { handle: "anotherhandle" }

    assert_redirected_to root_path
    # Handle should not change
    user.reload
    assert_equal "testuser", user.handle
  end

  test "create requires handle" do
    user = users(:user_without_handle)
    login_as(user)

    post handle_setups_path, params: { handle: "" }

    assert_response :unprocessable_entity
    assert_equal "Handle is required", flash[:alert]
  end

  test "create rejects existing handle" do
    user = users(:user_without_handle)
    login_as(user)

    post handle_setups_path, params: { handle: users(:test_user).handle }

    assert_response :unprocessable_entity
    assert_equal "This handle is already taken. Please choose another one.", flash[:alert]
  end

  test "create sets handle and redirects to root" do
    user = users(:user_without_handle)
    login_as(user)

    post handle_setups_path, params: { handle: "mynewhandle" }

    assert_redirected_to root_path
    assert_equal "Handle set successfully. Welcome to Retrofeed!", flash[:notice]

    user.reload
    assert_equal "mynewhandle", user.handle
  end

  test "create validates handle format" do
    user = users(:user_without_handle)
    login_as(user)

    post handle_setups_path, params: { handle: "123invalid" }

    assert_response :unprocessable_entity
    assert user.reload.handle.nil?
  end

  test "create validates handle length" do
    user = users(:user_without_handle)
    login_as(user)

    post handle_setups_path, params: { handle: "ab" }

    assert_response :unprocessable_entity
    assert user.reload.handle.nil?
  end
end
