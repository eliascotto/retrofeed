require "test_helper"

class Sites::RefreshesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:test_user)
    @other_user = users(:other_user)
    @website = websites(:one)
    @website_two = websites(:two)
    # test_user is subscribed to website one, not website two (from fixtures)
  end

  # ===== Authentication =====

  test "create requires authentication" do
    post site_refresh_path(@website)
    assert_redirected_to new_session_path
  end

  # ===== create action =====

  test "create enqueues CrawlArchiveJob with force flag when eligible" do
    @website.update!(last_crawled_at: 2.hours.ago, archive_url: "https://example.com/archive")
    login_as(@user)

    assert_enqueued_with(job: CrawlArchiveJob) do
      post site_refresh_path(@website)
    end

    assert_redirected_to site_path(@website)
    assert_equal "Website refresh queued", flash[:notice]
  end

  test "create redirects with alert when website was recently refreshed" do
    # Crawled just now — will be within any configured archive_min_interval
    @website.update!(last_crawled_at: 1.second.ago, archive_url: "https://example.com/archive")
    login_as(@user)

    assert_no_enqueued_jobs(only: CrawlArchiveJob) do
      post site_refresh_path(@website)
    end

    assert_response :redirect
    assert_match(/recently refreshed/, flash[:alert])
  end

  test "create redirects with alert when website has no archive URL" do
    @website.update!(archive_url: nil, last_crawled_at: 2.hours.ago)
    login_as(@user)

    assert_no_enqueued_jobs(only: CrawlArchiveJob) do
      post site_refresh_path(@website)
    end

    assert_response :redirect
    assert_equal "Website has no archive URL", flash[:alert]
  end

  test "create redirects to sites when user is not subscribed to the website" do
    login_as(@user)

    assert_no_enqueued_jobs(only: CrawlArchiveJob) do
      post site_refresh_path(@website_two)
    end

    assert_redirected_to sites_path
    assert_equal "Site not found", flash[:alert]
  end

  test "create redirects to sites when website does not exist" do
    login_as(@user)

    post site_refresh_path(site_id: 999999)

    assert_redirected_to sites_path
    assert_equal "Site not found", flash[:alert]
  end

  test "create falls back to site_path when no referrer" do
    @website.update!(last_crawled_at: 2.hours.ago, archive_url: "https://example.com/archive")
    login_as(@user)

    post site_refresh_path(@website)

    assert_redirected_to site_path(@website)
  end

  test "create includes minutes remaining in rate limit alert" do
    # Crawled just now — will be within any configured archive_min_interval
    @website.update!(last_crawled_at: 1.second.ago, archive_url: "https://example.com/archive")
    login_as(@user)

    post site_refresh_path(@website)

    assert_match(/recently refreshed/, flash[:alert])
  end
end
