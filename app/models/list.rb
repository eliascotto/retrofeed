class List < ApplicationRecord
  READ_NEXT_SLUG = "read-next".freeze
  SYSTEM_SLUGS = [ READ_NEXT_SLUG ].freeze

  # Restrict cover_image uploads to safe raster formats. SVG is intentionally
  # excluded because Active Storage refuses to serve it inline (XSS risk from
  # embedded scripts), which makes <img> tags fall back to alt text.
  COVER_IMAGE_CONTENT_TYPES = %w[ image/png image/jpeg image/webp image/gif ].freeze
  COVER_IMAGE_MAX_SIZE = 5.megabytes

  belongs_to :user

  # Cover image for the list (optional)
  has_one_attached :cover_image

  # Delete all list articles when the list is deleted
  has_many :list_articles, dependent: :destroy
  # Get all articles through the list articles
  has_many :articles, through: :list_articles

  validates :title, presence: true
  validates :title, length: { maximum: 100 }
  validates :title, uniqueness: { scope: :user_id }
  validates :description, length: { maximum: 500 }
  validates :slug, uniqueness: { scope: :user_id }, allow_nil: true
  validates :public_id, uniqueness: true, allow_nil: true
  validate :acceptable_cover_image

  # Generate public_id for URL sharing
  before_create :generate_public_id

  # Prevent deletion of system lists
  before_destroy :prevent_system_list_deletion

  # Scopes for visibility
  scope :public_lists, -> { where(public: true) }
  scope :private_lists, -> { where(public: false) }
  scope :system_lists, -> { where(slug: SYSTEM_SLUGS) }
  scope :user_lists, -> { where.not(slug: SYSTEM_SLUGS).or(where(slug: nil)) }

  # Check if this is a system list that cannot be deleted
  def system_list?
    SYSTEM_SLUGS.include?(slug)
  end

  # Check if this is the Read Next list
  def read_next?
    slug == READ_NEXT_SLUG
  end

  # Generate a URL-friendly identifier
  # System lists (like Read Next): use just the slug since they're unique per user
  # User lists: combine parameterized title with public_id for shareable URLs
  # Example: "my-reading-list-a8f2med"
  def public_slug
    if system_list?
      slug
    else
      [ title.parameterize.presence, public_id ].compact.join("-")
    end
  end

  # Override to_param so URL helpers use public_slug
  def to_param
    public_slug
  end

  # Find a list by its public slug
  # For system lists: matches by slug directly
  # For user lists: extracts public_id from the end of the slug
  def self.find_by_public_slug(public_slug_param)
    slug_param = public_slug_param.to_s
    if SYSTEM_SLUGS.include?(slug_param)
      find_by!(slug: slug_param)
    else
      public_id = slug_param.split("-").last
      find_by!(public_id: public_id)
    end
  end

  # Find a list by its public slug, scoped to a user
  def self.find_by_public_slug_for_user(public_slug_param, user)
    slug_param = public_slug_param.to_s
    if SYSTEM_SLUGS.include?(slug_param)
      user.lists.find_by!(slug: slug_param)
    else
      public_id = slug_param.split("-").last
      user.lists.find_by!(public_id: public_id)
    end
  end

  # Create the default Read Next list for a user
  def self.create_read_next_for(user)
    user.lists.create!(
      title: "Read Next",
      description: "Articles you want to read later",
      slug: READ_NEXT_SLUG,
      public: false
    )
  end

  # Add an article to this list at the end (optional position)
  def add_article(article, position: nil)
    position ||= list_articles.maximum(:position).to_i + 1
    list_articles.create!(article: article, position: position)
    :added
  end

  def remove_article(article)
    list_articles.find_by(article: article)&.destroy
  end

  def has_article?(article)
    list_articles.exists?(article: article)
  end

  # Reorder an article within this list
  def reorder_article(article, new_position)
    list_article = list_articles.find_by(article: article)
    list_article&.update(position: new_position)
  end

private
    def acceptable_cover_image
      return unless cover_image.attached?

      unless COVER_IMAGE_CONTENT_TYPES.include?(cover_image.content_type)
        errors.add(:cover_image, "must be a PNG, JPEG, WebP, or GIF image")
      end

      if cover_image.byte_size > COVER_IMAGE_MAX_SIZE
        errors.add(:cover_image, "must be smaller than #{COVER_IMAGE_MAX_SIZE / 1.megabyte} MB")
      end
    end

    # Generate a unique public_id for URL sharing
    # Retries up to 10 times if a collision occurs (extremely unlikely with 36^7 possibilities)
    MAX_PUBLIC_ID_RETRIES = 10

    # Length of the public_id
    # > 1M upgrade to 8
    # > 50M upgrade to 9
    ID_LENGTH = 7

    def generate_public_id
      MAX_PUBLIC_ID_RETRIES.times do
        candidate = SecureRandom.alphanumeric(ID_LENGTH).downcase
        unless List.exists?(public_id: candidate)
          self.public_id = candidate
          return
        end
      end

      raise "Failed to generate unique public_id after #{MAX_PUBLIC_ID_RETRIES} attempts"
    end

    def prevent_system_list_deletion
      # Allow system lists to be deleted when their user is being destroyed
      return if user.destroyed? || user.marked_for_destruction?

      if system_list?
        errors.add(:base, "System lists cannot be deleted")
        throw(:abort)
      end
    end
end
