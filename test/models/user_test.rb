require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "handle is not required for unconfirmed users" do
    user = User.new(email: "newunconfirmed@example.com", password: "password123", password_confirmation: "password123")
    assert user.valid?, "User should be valid without handle: #{user.errors.full_messages.join(', ')}"
    assert_empty user.errors[:handle]
  end

  test "handle is required for confirmed users" do
    user = User.new(email: "test@example.com", password: "password123", password_confirmation: "password123", email_confirmed_at: Time.current)
    assert_not user.valid?
    assert_includes user.errors[:handle], "can't be blank"
  end

  test "handle_setup_complete? returns true when handle is set" do
    user = users(:test_user)
    assert user.handle_setup_complete?
  end

  test "handle_setup_complete? returns false when handle is nil" do
    user = users(:user_without_handle)
    assert_not user.handle_setup_complete?
  end

  test "handle must be unique" do
    existing_user = users(:test_user)
    user = User.new(
      email: "different@example.com",
      handle: existing_user.handle,
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not user.valid?
    assert_includes user.errors[:handle], "has already been taken"
  end

  test "handle uniqueness is not case sensitive" do
    existing_user = users(:test_user)
    user = User.new(
      email: "different@example.com",
      handle: existing_user.handle.upcase,
      password: "password123",
      password_confirmation: "password123"
    )
    # Should be valid since handles are case-sensitive
    assert_not user.valid?
  end

  test "handle must start with a letter and contain only letters, numbers, and hyphens" do
    user = User.new(
      email: "test@example.com",
      handle: "123-abc",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not user.valid?
    assert_includes user.errors[:handle], "must start with a letter and contain only letters, numbers, and hyphens"

    user2 = User.new(
      email: "test2@example.com",
      handle: "-abc",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not user2.valid?
    assert_includes user2.errors[:handle], "must start with a letter and contain only letters, numbers, and hyphens"
  end

  test "handle cannot contain consecutive hyphens" do
    user = User.new(
      email: "test@example.com",
      handle: "test--handle",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not user.valid?
    assert_includes user.errors[:handle], "cannot contain consecutive hyphens"
  end

  test "handle cannot contain underscores" do
    user = User.new(
      email: "test@example.com",
      handle: "test_handle",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not user.valid?
    assert_includes user.errors[:handle], "must start with a letter and contain only letters, numbers, and hyphens"

    user2 = User.new(
      email: "test2@example.com",
      handle: "test.handle",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not user2.valid?
    assert_includes user2.errors[:handle], "must start with a letter and contain only letters, numbers, and hyphens"
  end

  test "handle must be between 3 and 25 characters" do
    user = User.new(
      email: "test@example.com",
      handle: "123",
      password: "password123",
      password_confirmation: "password123"
    )
    assert_not user.valid?
  end

  test "password cannot be the same as current password" do
    user = users(:test_user)
    user.password = "password123"
    user.password_confirmation = "password123"
    assert_not user.valid?
    assert_includes user.errors[:password], "cannot be the same as your current password"
  end

  test "password can be changed to a different password" do
    user = users(:test_user)
    user.password = "newpassword123"
    user.password_confirmation = "newpassword123"
    assert user.valid?
  end

  test "password validation only applies when password is being changed" do
    user = users(:test_user)
    user.handle = "newhandle"
    assert user.valid?
  end

  test "new user can set password" do
    user = User.new(
      email: "newuser@example.com",
      handle: "newuser",
      password: "password123",
      password_confirmation: "password123"
    )
    assert user.valid?
  end

  test "password must be at least 8 characters" do
    user = User.new(
      email: "newuser@example.com",
      handle: "newuser",
      password: "short",
      password_confirmation: "short"
    )
    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 8 characters)"
  end

  test "password can be exactly 8 characters" do
    user = User.new(
      email: "newuser@example.com",
      handle: "newuser",
      password: "12345678",
      password_confirmation: "12345678"
    )
    assert user.valid?
  end

  test "password cannot exceed 72 characters" do
    long_password = "a" * 73
    user = User.new(
      email: "newuser@example.com",
      handle: "newuser",
      password: long_password,
      password_confirmation: long_password
    )
    assert_not user.valid?
    assert_includes user.errors[:password], "is too long (maximum is 72 characters)"
  end

  test "password can be exactly 72 characters" do
    long_password = "a" * 72
    user = User.new(
      email: "newuser@example.com",
      handle: "newuser",
      password: long_password,
      password_confirmation: long_password
    )
    assert user.valid?
  end

  test "password length validation only applies when password is being changed" do
    user = users(:test_user)
    user.handle = "newhandle"
    assert user.valid?
  end

  # ===== Reading Lists tests =====

  test "reading_lists returns user-created lists only" do
    user = users(:test_user)

    # Create a user list
    user_list = user.lists.create!(title: "User Created List")

    # Get reading lists
    reading_lists = user.reading_lists

    # Should include the user list
    assert_includes reading_lists, user_list

    # Should not include the read-next list
    read_next = user.read_next_list
    assert_not_includes reading_lists, read_next if read_next
  end

  test "reading_lists returns lists ordered by title" do
    user = users(:test_user)

    # Create lists in non-alphabetical order
    user.lists.create!(title: "Zebra List")
    user.lists.create!(title: "Alpha List")
    user.lists.create!(title: "Beta List")

    reading_lists = user.reading_lists

    assert_equal "Alpha List", reading_lists.first.title
    assert_equal "Zebra List", reading_lists.last.title
  end

  test "reading_lists returns empty when user has no custom lists" do
    user = users(:other_user)

    # Ensure user has no custom lists (may have read-next from after_create callback)
    user.lists.user_lists.destroy_all

    reading_lists = user.reading_lists

    assert_empty reading_lists
  end

  # ===== read_next_list tests =====

  test "read_next_list returns the users read next list" do
    user = users(:test_user)
    read_next = user.read_next_list

    assert_not_nil read_next
    assert_equal "read-next", read_next.slug
    assert_equal user.id, read_next.user_id
  end

  test "read_next_list returns nil when user has no read next list" do
    user = users(:other_user)
    # Delete the read-next list if it exists
    user.lists.where(slug: "read-next").destroy_all

    assert_nil user.read_next_list
  end

  # ===== unread_articles tests =====

  test "unread_articles returns articles from subscribed sites without reading state" do
    user = users(:test_user)
    website = websites(:one)

    # Create an unread article
    unread_article = Article.create!(
      website: website,
      title: "Unread Article",
      url: "https://example.com/unread",
      content_html: "<p>Content</p>"
    )

    unread_articles = user.unread_articles

    assert_includes unread_articles, unread_article
  end

  test "unread_articles excludes articles marked as read" do
    user = users(:test_user)
    # Article one has reading state with read_at from fixtures
    article_one = articles(:one)

    unread_articles = user.unread_articles

    assert_not_includes unread_articles, article_one
  end

  test "unread_articles excludes articles from unsubscribed sites" do
    user = users(:test_user)
    website_two = websites(:two)

    # Create article for unsubscribed site
    other_article = Article.create!(
      website: website_two,
      title: "Other Site Article",
      url: "https://example2.com/other",
      content_html: "<p>Content</p>"
    )

    unread_articles = user.unread_articles

    assert_not_includes unread_articles, other_article
  end

  # ===== unread_articles_for_website tests =====

  test "unread_articles_for_website returns unread articles for specific site" do
    user = users(:test_user)
    website = websites(:one)

    # Create an unread article
    unread_article = Article.create!(
      website: website,
      title: "Unread Article",
      url: "https://example.com/unread-specific",
      content_html: "<p>Content</p>"
    )

    unread_articles = user.unread_articles_for_website(website)

    assert_includes unread_articles, unread_article
  end

  test "unread_articles_for_website excludes read articles" do
    user = users(:test_user)
    website = websites(:one)
    article_one = articles(:one)

    unread_articles = user.unread_articles_for_website(website)

    # Article one has reading state from fixtures
    assert_not_includes unread_articles, article_one
  end

  test "unread_articles_for_website orders by publication date desc" do
    user = users(:test_user)
    website = websites(:one)

    older_article = Article.create!(
      website: website,
      title: "Older Article",
      url: "https://example.com/older",
      content_html: "<p>Content</p>",
      publication_date: 1.week.ago
    )

    newer_article = Article.create!(
      website: website,
      title: "Newer Article",
      url: "https://example.com/newer",
      content_html: "<p>Content</p>",
      publication_date: Date.today
    )

    unread_articles = user.unread_articles_for_website(website)

    # Newer article should come first
    assert_equal newer_article, unread_articles.first
  end

  # ===== reading_articles tests =====

  test "reading_articles returns articles with reading state but no read_at" do
    user = users(:test_user)
    website = websites(:one)

    in_progress_article = Article.create!(
      website: website,
      title: "In Progress Article",
      url: "https://example.com/in-progress",
      content_html: "<p>Content</p>"
    )

    # Create reading state without read_at
    UserArticle.create!(user: user, article: in_progress_article, read_at: nil)

    reading_articles = user.reading_articles

    assert_includes reading_articles, in_progress_article
  end

  test "reading_articles excludes finished articles" do
    user = users(:test_user)
    article_one = articles(:one)

    # Article one has reading state with read_at from fixtures
    reading_articles = user.reading_articles

    assert_not_includes reading_articles, article_one
  end

  test "reading_articles excludes articles without reading state" do
    user = users(:test_user)
    website = websites(:one)

    never_opened_article = Article.create!(
      website: website,
      title: "Never Opened Article",
      url: "https://example.com/never-opened",
      content_html: "<p>Content</p>"
    )

    reading_articles = user.reading_articles

    assert_not_includes reading_articles, never_opened_article
  end

  test "reading_articles orders by last opened" do
    user = users(:test_user)
    website = websites(:one)

    earlier_article = Article.create!(
      website: website,
      title: "Earlier Article",
      url: "https://example.com/earlier",
      content_html: "<p>Content</p>"
    )

    later_article = Article.create!(
      website: website,
      title: "Later Article",
      url: "https://example.com/later",
      content_html: "<p>Content</p>"
    )

    # Create reading states with different updated_at times
    UserArticle.create!(user: user, article: earlier_article, read_at: nil, updated_at: 1.hour.ago)
    UserArticle.create!(user: user, article: later_article, read_at: nil, updated_at: Time.current)

    reading_articles = user.reading_articles

    # Most recently opened should come first
    assert_equal later_article, reading_articles.first
  end

  # ===== reading_settings tests =====

  test "reading_settings returns defaults when no settings saved" do
    user = users(:test_user)
    user.settings = {}

    settings = user.reading_settings

    assert_equal "base", settings["font_size"]
    assert_equal "sans", settings["font_family"]
    assert_equal "system", settings["theme"]
    assert_equal "default", settings["content_width"]
  end

  test "reading_settings merges saved settings with defaults" do
    user = users(:test_user)
    user.settings = { "reading" => { "font_size" => "lg" } }

    settings = user.reading_settings

    assert_equal "lg", settings["font_size"]
    assert_equal "sans", settings["font_family"]  # Default
  end

  # ===== update_reading_settings tests =====

  test "update_reading_settings saves valid settings" do
    user = users(:test_user)

    result = user.update_reading_settings({
      "font_size" => "lg",
      "font_family" => "serif",
      "theme" => "dark",
      "content_width" => "wide"
    })

    assert result
    user.reload
    settings = user.reading_settings
    assert_equal "lg", settings["font_size"]
    assert_equal "serif", settings["font_family"]
    assert_equal "dark", settings["theme"]
    assert_equal "wide", settings["content_width"]
  end

  test "update_reading_settings ignores invalid values" do
    user = users(:test_user)

    user.update_reading_settings({
      "font_size" => "invalid",
      "font_family" => "comic-sans",
      "theme" => "rainbow"
    })

    user.reload
    settings = user.reading_settings
    # Should remain at defaults since invalid values are ignored
    assert_equal "base", settings["font_size"]
    assert_equal "sans", settings["font_family"]
    assert_equal "system", settings["theme"]
  end

  # ===== home_tab_preference tests =====

  test "home_tab_preference returns saved preference" do
    user = users(:test_user)
    user.settings = { "home_tab" => "reading" }
    user.save!

    assert_equal "reading", user.home_tab_preference
  end

  test "home_tab_preference returns default for invalid value" do
    user = users(:test_user)
    user.settings = { "home_tab" => "invalid" }
    user.save!

    assert_equal "recent", user.home_tab_preference
  end

  test "home_tab_preference returns default when not set" do
    user = users(:test_user)
    user.settings = {}
    user.save!

    assert_equal "recent", user.home_tab_preference
  end

  # ===== update_home_tab_preference tests =====

  test "update_home_tab_preference saves valid tab" do
    user = users(:test_user)

    result = user.update_home_tab_preference("reading")

    assert result
    user.reload
    assert_equal "reading", user.home_tab_preference
  end

  test "update_home_tab_preference rejects invalid tab" do
    user = users(:test_user)
    user.settings = { "home_tab" => "recent" }
    user.save!

    result = user.update_home_tab_preference("invalid")

    assert_not result
    user.reload
    assert_equal "recent", user.home_tab_preference
  end

  # ===== after_create callback tests =====

  test "new user gets read next list automatically" do
    user = User.create!(
      email: "newcallback@example.com",
      handle: "newcallback",
      password: "password123",
      password_confirmation: "password123"
    )

    read_next = user.read_next_list

    assert_not_nil read_next
    assert_equal "Read Next", read_next.title
    assert_equal "read-next", read_next.slug
  end

  # ===== admin? tests =====

  test "admin? returns true for admin user" do
    admin = users(:admin)
    assert admin.admin?
  end

  test "admin? returns false for regular user" do
    user = users(:test_user)
    assert_not user.admin?
  end

  test "subscribe_to_url creates website and enqueues ProcessWebsiteJob for new domain" do
    user = users(:test_user)

    assert_enqueued_with(job: ProcessWebsiteJob) do
      website = user.subscribe_to_url("https://newblog.example.com/")
      assert_equal "newblog.example.com", website.domain
      assert user.subscriptions.exists?(website: website)
    end
  end

  test "subscribe_to_url raises AlreadySubscribedError when already subscribed" do
    user = users(:test_user)
    website = Website.create!(domain: "subscribed.example.com", name: "Subscribed", processing_status: "completed")
    Subscription.create!(user: user, website: website)

    assert_raises(User::AlreadySubscribedError) do
      user.subscribe_to_url("https://subscribed.example.com/")
    end
  end

  test "subscribe_to_url re-enqueues ProcessWebsiteJob for existing website with no articles" do
    user = users(:test_user)
    website = Website.create!(domain: "empty-completed.example.com", name: "Empty", processing_status: "completed")

    assert_enqueued_with(job: ProcessWebsiteJob) do
      result = user.subscribe_to_url("https://empty-completed.example.com/")
      assert_equal "pending", result.reload.processing_status
      assert user.subscriptions.exists?(website: website)
    end
  end

  test "subscribe_to_url does not re-enqueue ProcessWebsiteJob for existing website that has articles" do
    user = users(:test_user)
    website = Website.create!(domain: "has-articles.example.com", name: "Has Articles", processing_status: "completed")
    website.articles.create!(url: "https://has-articles.example.com/post-1", title: "Post 1", status: "completed")

    assert_no_enqueued_jobs(only: ProcessWebsiteJob) do
      user.subscribe_to_url("https://has-articles.example.com/")
    end
  end

  test "subscribe_to_url re-enqueues ProcessWebsiteJob for failed website" do
    user = users(:test_user)
    website = Website.create!(domain: "failed-site.example.com", name: "Failed", processing_status: "failed")

    assert_enqueued_with(job: ProcessWebsiteJob) do
      result = user.subscribe_to_url("https://failed-site.example.com/")
      assert_equal "pending", result.reload.processing_status
    end
  end
end
