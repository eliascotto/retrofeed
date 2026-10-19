require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  setup do
    @user = users(:test_user)
    @other_user = users(:other_user)
    @website = websites(:one)
    @website_two = websites(:two)
    @article = articles(:one)
  end

  # ===== Validation tests =====

  test "valid with user and website" do
    # First remove existing subscription if any
    Subscription.where(user: @other_user, website: @website).destroy_all

    subscription = Subscription.new(user: @other_user, website: @website)
    assert subscription.valid?
  end

  test "user must be unique per website" do
    # Ensure subscription exists (from fixtures)
    assert Subscription.exists?(user: @user, website: @website)

    duplicate = Subscription.new(user: @user, website: @website)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "same user can subscribe to different websites" do
    # User already subscribed to website_one, can subscribe to website_two
    subscription = Subscription.new(user: @user, website: @website_two)
    assert subscription.valid?
  end

  test "same website can have different users subscribed" do
    # website_one already has test_user, admin can also subscribe
    admin = users(:admin)
    # First ensure subscription exists for admin (from fixtures)
    # Or create new one if not exists
    subscription = Subscription.find_or_initialize_by(user: admin, website: @website)
    assert subscription.valid?
  end

  # ===== Association tests =====

  test "belongs to user" do
    subscription = subscriptions(:one)
    assert_equal @user, subscription.user
  end

  test "belongs to website" do
    subscription = subscriptions(:one)
    assert_equal @website, subscription.website
  end

  # ===== Cascade cleanup tests =====

  test "deleting subscription removes reading states for that user and website" do
    # Create a new subscription to test with
    Subscription.find_or_create_by!(user: @other_user, website: @website)

    # Create an article for this website
    article = Article.create!(
      website: @website,
      title: "Test Article",
      url: "https://example.com/cascade-test",
      content_html: "<p>Content</p>"
    )

    # Create reading state for this user and article
    user_article = UserArticle.create!(
      user: @other_user,
      article: article,
      read_at: Time.current
    )
    user_article_id = user_article.id

    # Delete the subscription
    Subscription.find_by(user: @other_user, website: @website).destroy

    # Reading state should be deleted
    assert_not UserArticle.exists?(user_article_id)
  end

  test "deleting subscription does not remove reading states for other users" do
    # Ensure other_user has subscription
    Subscription.find_or_create_by!(user: @other_user, website: @website)

    # Create article
    article = Article.create!(
      website: @website,
      title: "Test Article Multi User",
      url: "https://example.com/cascade-multi",
      content_html: "<p>Content</p>"
    )

    # Create reading states for both users
    user_article_other = UserArticle.create!(
      user: @other_user,
      article: article,
      read_at: Time.current
    )
    user_article_test = UserArticle.create!(
      user: @user,
      article: article,
      read_at: Time.current
    )
    user_article_test_id = user_article_test.id

    # Delete other_user's subscription
    Subscription.find_by(user: @other_user, website: @website).destroy

    # test_user's reading state should still exist
    assert UserArticle.exists?(user_article_test_id)
  end

  test "deleting subscription does not remove reading states for other websites" do
    # Ensure user has subscription to website_two
    Subscription.find_or_create_by!(user: @user, website: @website_two)

    # Create article for website_two
    article_two = Article.create!(
      website: @website_two,
      title: "Other Site Article",
      url: "https://example2.com/cascade-site",
      content_html: "<p>Content</p>"
    )

    # Create reading state for website_two article
    user_article = UserArticle.create!(
      user: @user,
      article: article_two,
      read_at: Time.current
    )
    user_article_id = user_article.id

    # Delete subscription to website_one
    Subscription.find_by(user: @user, website: @website).destroy

    # Reading state for website_two should still exist
    assert UserArticle.exists?(user_article_id)
  end

  test "deleting subscription removes article tags for that user and website" do
    # Ensure subscription exists
    Subscription.find_or_create_by!(user: @other_user, website: @website)

    # Create article
    article = Article.create!(
      website: @website,
      title: "Tagged Article",
      url: "https://example.com/tagged-cascade",
      content_html: "<p>Content</p>"
    )

    # Create tag for user and associate with article
    tag = Tag.create!(user: @other_user, name: "Test Tag Cascade")
    article_tag = ArticleTag.create!(article: article, tag: tag)
    article_tag_id = article_tag.id

    # Delete subscription
    Subscription.find_by(user: @other_user, website: @website).destroy

    # Article tag should be deleted
    assert_not ArticleTag.exists?(article_tag_id)
  end

  test "deleting subscription does not remove article tags for other users" do
    # Ensure subscriptions exist
    Subscription.find_or_create_by!(user: @other_user, website: @website)

    # Create article
    article = Article.create!(
      website: @website,
      title: "Multi Tag Article",
      url: "https://example.com/multi-tag-cascade",
      content_html: "<p>Content</p>"
    )

    # Create tags for both users
    tag_other = Tag.create!(user: @other_user, name: "Other User Tag")
    tag_test = Tag.create!(user: @user, name: "Test User Tag")
    ArticleTag.create!(article: article, tag: tag_other)
    article_tag_test = ArticleTag.create!(article: article, tag: tag_test)
    article_tag_test_id = article_tag_test.id

    # Delete other_user's subscription
    Subscription.find_by(user: @other_user, website: @website).destroy

    # test_user's article tag should still exist
    assert ArticleTag.exists?(article_tag_test_id)
  end

  # ===== Destroy behavior tests =====

  test "destroying subscription removes it from database" do
    # Use find_or_create to handle existing fixture
    subscription = Subscription.find_or_create_by!(user: @other_user, website: @website_two)
    subscription_id = subscription.id

    subscription.destroy

    assert_not Subscription.exists?(subscription_id)
  end

  test "user no longer has website after subscription destroyed" do
    # Ensure subscription exists
    Subscription.find_or_create_by!(user: @other_user, website: @website_two)
    assert @other_user.websites.include?(@website_two)

    # Destroy subscription
    Subscription.find_by(user: @other_user, website: @website_two).destroy

    # Reload and check
    @other_user.reload
    assert_not @other_user.websites.include?(@website_two)
  end

  # ===== Turbo Stream broadcast tests =====

  test "create broadcasts a site-list prepend, empty-state removal, and counter replace" do
    # Use a fresh user/website pair so we only capture broadcasts from this create.
    user = users(:unconfirmed_user)
    website = @website_two
    Subscription.where(user: user).destroy_all

    payloads = capture_broadcasts("user_#{user.id}") do
      perform_enqueued_jobs do
        Subscription.create!(user: user, website: website)
      end
    end

    joined = payloads.join
    assert_match %r{action="prepend"[^>]*target="sites-list"},        joined
    assert_match %r{action="remove"[^>]*target="sites-empty-state"},  joined
    assert_match %r{action="replace"[^>]*target="sites-counter"},     joined
  end

  test "destroy broadcasts row removal and counter replace when other subscriptions remain" do
    # Admin keeps a subscription to @website even after we destroy the test_user's,
    # but we capture on test_user's stream — what matters is test_user has another sub.
    Subscription.find_or_create_by!(user: @user, website: @website_two)
    subscription = Subscription.find_by!(user: @user, website: @website)

    payloads = capture_broadcasts("user_#{@user.id}") do
      subscription.destroy
    end

    joined = payloads.join
    assert_match %r{action="remove"[^>]*target="website_#{@website.id}"}, joined
    assert_match %r{action="replace"[^>]*target="sites-counter"},          joined
    # Empty state must NOT reappear while other subscriptions exist.
    assert_no_match %r{target="sites-list"}, joined
    assert_no_match /No websites yet/,       joined
  end

  test "destroy of last subscription also appends the empty state" do
    user = users(:unconfirmed_user)
    Subscription.where(user: user).destroy_all
    subscription = Subscription.create!(user: user, website: @website_two)

    payloads = capture_broadcasts("user_#{user.id}") do
      subscription.destroy
    end

    joined = payloads.join
    assert_match %r{action="remove"[^>]*target="website_#{@website_two.id}"}, joined
    assert_match %r{action="replace"[^>]*target="sites-counter"},              joined
    assert_match %r{action="append"[^>]*target="sites-list"},                  joined
    # Sanity-check the empty-state partial actually rendered.
    assert_match /No websites yet/, joined
  end
end
