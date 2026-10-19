require "test_helper"

class SetPlatformTest < ActionDispatch::IntegrationTest
  DESKTOP_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  NATIVE_IOS_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Hotwire Native iOS/1.0 bridge-components: [buttons overflow-menu]"

  setup do
    @user = users(:test_user)
  end

  test "uses the request user agent by default" do
    login_as(@user)

    get root_path, headers: { "User-Agent" => DESKTOP_UA }
    assert_select "body[data-platform='desktop web']"
  end

  test "prefers x_user_agent cookie over request user agent" do
    login_as(@user)

    cookies[:x_user_agent] = NATIVE_IOS_UA
    get root_path, headers: { "User-Agent" => DESKTOP_UA }
    assert_select "body[data-platform='native ios']"
  end
end
