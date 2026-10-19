require "test_helper"

class CsrfProtectionTest < ActionDispatch::IntegrationTest
  setup do
    login_as(:test_user)
    @original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @original
    logout
  end

  test "rejects post without csrf token" do
    post sites_path, params: { site: { url: "https://excalibur.com" } }
    assert_response :unprocessable_entity
  end
end
