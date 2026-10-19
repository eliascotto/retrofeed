require "test_helper"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:test_user)
    @other_user = users(:other_user)
    @website = websites(:one)
    @website_two = websites(:two)
    # test_user is subscribed to website one (from fixtures)
    # other_user is subscribed to website two (from fixtures)
  end

  # ===== Authentication tests =====

  test "destroy requires authentication" do
    delete site_subscription_path(@website)
    assert_redirected_to new_session_path
  end

  # ===== destroy action tests =====

  test "destroy removes subscription" do
    login_as(@user)

    assert_difference "Subscription.count", -1 do
      delete site_subscription_path(@website)
    end

    assert_nil @user.subscriptions.find_by(website: @website)
  end

  test "destroy redirects back with notice" do
    login_as(@user)

    delete site_subscription_path(@website), headers: { "HTTP_REFERER" => sites_path }

    assert_redirected_to sites_path
    assert_equal "Site removed", flash[:notice]
  end

  test "destroy redirects to sites_path when no referer" do
    login_as(@user)

    delete site_subscription_path(@website)

    assert_redirected_to sites_path
    assert_equal "Site removed", flash[:notice]
  end

  test "destroy handles non-existent subscription" do
    login_as(@user)

    # test_user is not subscribed to website_two
    assert_no_difference "Subscription.count" do
      delete site_subscription_path(@website_two)
    end

    assert_redirected_to sites_path
    assert_equal "Subscription not found", flash[:alert]
  end

  test "destroy handles non-existent website" do
    login_as(@user)

    delete site_subscription_path(site_id: 999999)

    assert_redirected_to sites_path
    assert_equal "Site not found", flash[:alert]
  end

  test "destroy does not affect other users subscriptions" do
    login_as(@user)

    # Create subscription for other user to the same website
    other_subscription = Subscription.create!(user: @other_user, website: @website)

    delete site_subscription_path(@website)

    # other_user's subscription should still exist
    assert Subscription.exists?(other_subscription.id)
  end

  test "destroy resets user association cache" do
    login_as(@user)

    # Access the association to cache it
    @user.subscriptions.to_a
    @user.websites.to_a

    delete site_subscription_path(@website)

    # User should no longer see the website in their subscriptions
    @user.reload
    assert_not @user.websites.include?(@website)
  end
end
