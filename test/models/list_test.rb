require "test_helper"

class ListTest < ActiveSupport::TestCase
  setup do
    @user = users(:test_user)
    @other_user = users(:other_user)
    @article = articles(:one)
  end

  # ===== Validation tests =====

  test "title must be present" do
    list = List.new(user: @user, title: nil)
    assert_not list.valid?
    assert_includes list.errors[:title], "can't be blank"
  end

  test "title cannot be blank" do
    list = List.new(user: @user, title: "")
    assert_not list.valid?
    assert_includes list.errors[:title], "can't be blank"
  end

  test "title cannot exceed 100 characters" do
    list = List.new(user: @user, title: "a" * 101)
    assert_not list.valid?
    assert_includes list.errors[:title], "is too long (maximum is 100 characters)"
  end

  test "title can be exactly 100 characters" do
    list = List.new(user: @user, title: "a" * 100)
    assert list.valid?
  end

  test "title must be unique per user" do
    existing_list = lists(:user_list)
    list = List.new(user: @user, title: existing_list.title)
    assert_not list.valid?
    assert_includes list.errors[:title], "has already been taken"
  end

  test "same title allowed for different users" do
    existing_list = lists(:user_list)
    list = List.new(user: @other_user, title: existing_list.title)
    assert list.valid?
  end

  test "description cannot exceed 500 characters" do
    list = List.new(user: @user, title: "Test List", description: "a" * 501)
    assert_not list.valid?
    assert_includes list.errors[:description], "is too long (maximum is 500 characters)"
  end

  test "description can be exactly 500 characters" do
    list = List.new(user: @user, title: "Test List", description: "a" * 500)
    assert list.valid?
  end

  test "description is optional" do
    list = List.new(user: @user, title: "Test List", description: nil)
    assert list.valid?
  end

  test "slug must be unique per user" do
    # Create a list with a slug
    list1 = List.create!(user: @user, title: "List One", slug: "custom-slug")
    list2 = List.new(user: @user, title: "List Two", slug: "custom-slug")
    assert_not list2.valid?
    assert_includes list2.errors[:slug], "has already been taken"
  end

  test "same slug allowed for different users" do
    list1 = List.create!(user: @user, title: "List One", slug: "custom-slug")
    list2 = List.new(user: @other_user, title: "List Two", slug: "custom-slug")
    assert list2.valid?
  end

  test "slug can be nil" do
    list = List.new(user: @user, title: "Test List", slug: nil)
    assert list.valid?
  end

  test "public_id must be unique" do
    list1 = List.create!(user: @user, title: "List One")
    list2 = List.new(user: @other_user, title: "List Two")
    list2.public_id = list1.public_id
    assert_not list2.valid?
    assert_includes list2.errors[:public_id], "has already been taken"
  end

  # ===== cover_image validation tests =====

  test "cover_image is optional" do
    list = List.new(user: @user, title: "No cover")
    assert list.valid?
  end

  test "cover_image accepts an allowed content type" do
    list = List.new(user: @user, title: "With PNG cover")
    list.cover_image.attach(io: StringIO.new("png-bytes"), filename: "cover.png", content_type: "image/png")

    assert list.valid?, list.errors.full_messages.inspect
  end

  test "cover_image rejects disallowed content types like SVG" do
    list = List.new(user: @user, title: "SVG cover")
    list.cover_image.attach(io: StringIO.new("<svg/>"), filename: "cover.svg", content_type: "image/svg+xml")

    assert_not list.valid?
    assert_includes list.errors[:cover_image], "must be a PNG, JPEG, WebP, or GIF image"
  end

  test "cover_image rejects files larger than the size limit" do
    list = List.new(user: @user, title: "Oversized cover")
    oversized = "x" * (List::COVER_IMAGE_MAX_SIZE + 1)
    list.cover_image.attach(io: StringIO.new(oversized), filename: "big.png", content_type: "image/png")

    assert_not list.valid?
    assert_includes list.errors[:cover_image], "must be smaller than 5 MB"
  end

  # ===== public_id generation tests =====

  test "public_id is generated on create" do
    list = List.create!(user: @user, title: "New List")
    assert_not_nil list.public_id
    assert_equal 7, list.public_id.length
  end

  test "public_id is lowercase alphanumeric" do
    list = List.create!(user: @user, title: "New List")
    assert_match(/\A[a-z0-9]+\z/, list.public_id)
  end

  test "public_id is unique across lists" do
    ids = 10.times.map do |i|
      List.create!(user: @user, title: "List #{i}").public_id
    end
    assert_equal ids.length, ids.uniq.length
  end

  # ===== system_list? tests =====

  test "system_list? returns true for read-next slug" do
    list = lists(:read_next_list)
    assert list.system_list?
  end

  test "system_list? returns false for user lists" do
    list = lists(:user_list)
    assert_not list.system_list?
  end

  test "system_list? returns false for nil slug" do
    list = List.new(user: @user, title: "Test", slug: nil)
    assert_not list.system_list?
  end

  # ===== read_next? tests =====

  test "read_next? returns true for read-next slug" do
    list = lists(:read_next_list)
    assert list.read_next?
  end

  test "read_next? returns false for user lists" do
    list = lists(:user_list)
    assert_not list.read_next?
  end

  # ===== public_slug tests =====

  test "public_slug returns slug for system lists" do
    list = lists(:read_next_list)
    assert_equal "read-next", list.public_slug
  end

  test "public_slug returns parameterized title with public_id for user lists" do
    list = lists(:user_list)
    expected = "#{list.title.parameterize}-#{list.public_id}"
    assert_equal expected, list.public_slug
  end

  test "public_slug handles title with special characters" do
    list = List.create!(user: @user, title: "My Favorite Articles!")
    assert_match(/my-favorite-articles-[a-z0-9]+/, list.public_slug)
  end

  test "public_slug handles numeric title" do
    list = List.create!(user: @user, title: "123")
    # Numbers parameterize to "123", so slug is "123-<public_id>"
    assert_equal "123-#{list.public_id}", list.public_slug
  end

  # ===== to_param tests =====

  test "to_param returns public_slug" do
    list = lists(:user_list)
    assert_equal list.public_slug, list.to_param
  end

  # ===== find_by_public_slug tests =====

  test "find_by_public_slug finds system list by slug" do
    # find_by_public_slug finds any list with the system slug
    # Since multiple users can have read-next, just verify it finds one
    found = List.find_by_public_slug("read-next")
    assert_not_nil found
    assert_equal "read-next", found.slug
    assert found.system_list?
  end

  test "find_by_public_slug finds user list by public_id" do
    list = lists(:user_list)
    found = List.find_by_public_slug(list.public_slug)
    assert_equal list, found
  end

  test "find_by_public_slug extracts public_id from end of slug" do
    list = lists(:user_list)
    # Should work with any prefix as long as public_id is at the end
    found = List.find_by_public_slug("anything-here-#{list.public_id}")
    assert_equal list, found
  end

  test "find_by_public_slug raises RecordNotFound for non-existent system slug" do
    assert_raises(ActiveRecord::RecordNotFound) do
      List.find_by_public_slug("nonexistent-system-slug")
    end
  end

  test "find_by_public_slug raises RecordNotFound for non-existent public_id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      List.find_by_public_slug("my-list-zzzzzzz")
    end
  end

  # ===== find_by_public_slug_for_user tests =====

  test "find_by_public_slug_for_user finds system list for correct user" do
    list = lists(:read_next_list)
    found = List.find_by_public_slug_for_user("read-next", @user)
    assert_equal list, found
  end

  test "find_by_public_slug_for_user raises for system list of different user" do
    assert_raises(ActiveRecord::RecordNotFound) do
      List.find_by_public_slug_for_user("read-next", @other_user)
    end
  end

  test "find_by_public_slug_for_user finds user list for correct user" do
    list = lists(:user_list)
    found = List.find_by_public_slug_for_user(list.public_slug, @user)
    assert_equal list, found
  end

  test "find_by_public_slug_for_user raises for user list of different user" do
    list = lists(:user_list)
    assert_raises(ActiveRecord::RecordNotFound) do
      List.find_by_public_slug_for_user(list.public_slug, @other_user)
    end
  end

  # ===== create_read_next_for tests =====

  test "create_read_next_for creates read next list for user" do
    # other_user doesn't have a read-next list in fixtures
    @other_user.lists.where(slug: "read-next").destroy_all

    list = List.create_read_next_for(@other_user)

    assert_equal "Read Next", list.title
    assert_equal "Articles you want to read later", list.description
    assert_equal "read-next", list.slug
    assert_not list.public
    assert_equal @other_user, list.user
  end

  # ===== add_article tests =====

  test "add_article adds article to list" do
    list = lists(:user_list)
    initial_count = list.articles.count

    list.add_article(@article)

    assert_equal initial_count + 1, list.articles.count
    assert_includes list.articles, @article
  end

  test "add_article assigns incrementing position" do
    list = lists(:user_list)
    article2 = articles(:two)

    list.add_article(@article)
    list.add_article(article2)

    positions = list.list_articles.order(:position).pluck(:position)
    assert_equal [ 1, 2 ], positions
  end

  test "add_article with custom position" do
    list = lists(:user_list)

    list.add_article(@article, position: 5)

    list_article = list.list_articles.find_by(article: @article)
    assert_equal 5, list_article.position
  end

  test "add_article raises on duplicate" do
    list = lists(:user_list)
    list.add_article(@article)

    assert_raises(ActiveRecord::RecordInvalid) do
      list.add_article(@article)
    end
  end

  # ===== remove_article tests =====

  test "remove_article removes article from list" do
    list = lists(:user_list)
    list.add_article(@article)

    list.remove_article(@article)

    assert_not_includes list.articles.reload, @article
  end

  test "remove_article returns nil for article not in list" do
    list = lists(:user_list)
    result = list.remove_article(@article)
    assert_nil result
  end

  # ===== reorder_article tests =====

  test "reorder_article updates position" do
    list = lists(:user_list)
    list.add_article(@article, position: 1)

    list.reorder_article(@article, 10)

    list_article = list.list_articles.find_by(article: @article)
    assert_equal 10, list_article.position
  end

  test "reorder_article returns nil for article not in list" do
    list = lists(:user_list)
    result = list.reorder_article(@article, 5)
    assert_nil result
  end

  # ===== prevent_system_list_deletion tests =====

  test "cannot delete system list" do
    list = lists(:read_next_list)

    assert_not list.destroy
    assert_includes list.errors[:base], "System lists cannot be deleted"
    assert List.exists?(list.id)
  end

  test "can delete user list" do
    list = lists(:user_list)

    assert list.destroy
    assert_not List.exists?(list.id)
  end

  # ===== Scope tests =====

  test "public_lists scope returns only public lists" do
    public_list = List.create!(user: @user, title: "Public List", public: true)
    private_list = List.create!(user: @user, title: "Private List", public: false)

    public_lists = List.public_lists

    assert_includes public_lists, public_list
    assert_not_includes public_lists, private_list
  end

  test "private_lists scope returns only private lists" do
    public_list = List.create!(user: @user, title: "Public List", public: true)
    private_list = List.create!(user: @user, title: "Private List", public: false)

    private_lists = List.private_lists

    assert_includes private_lists, private_list
    assert_not_includes private_lists, public_list
  end

  test "system_lists scope returns only system lists" do
    system_list = lists(:read_next_list)
    user_list = lists(:user_list)

    system_lists = List.system_lists

    assert_includes system_lists, system_list
    assert_not_includes system_lists, user_list
  end

  test "user_lists scope returns non-system lists" do
    system_list = lists(:read_next_list)
    user_list = lists(:user_list)

    user_lists = List.user_lists

    assert_includes user_lists, user_list
    assert_not_includes user_lists, system_list
  end

  # ===== Association tests =====

  test "deleting list deletes list_articles" do
    list = lists(:user_list)
    list.add_article(@article)
    list_article_id = list.list_articles.first.id

    list.destroy

    assert_not ListArticle.exists?(list_article_id)
  end
end
