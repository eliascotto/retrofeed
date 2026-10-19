class User < ApplicationRecord
  AlreadySubscribedError = Class.new(StandardError)

  has_secure_password

  CONFIRMATION_TOKEN_TTL = 24.hours
  PASSWORD_RESET_TOKEN_TTL = 15.minutes

  # ====================
  # Token generation
  # ====================

  # Signed, self-expiring email confirmation token. Not stored in the database.
  # Invalidated when the target email changes, and once the email is confirmed
  # (email_confirmed_at changes), making the link single-use.
  generates_token_for :email_confirmation, expires_in: CONFIRMATION_TOKEN_TTL do
    [ unconfirmed_email || email, email_confirmed_at&.to_i ]
  end

  # Signed, self-expiring password reset token. Not stored in the database.
  # has_secure_password changes the salt when the password is updated, so the
  # token becomes invalid as soon as the password is reset, making it single-use.
  generates_token_for :password_reset, expires_in: PASSWORD_RESET_TOKEN_TTL do
    password_salt&.last(10)
  end

  # ====================
  # Validations
  # ====================

  # Password validations
  validates :password, length: { minimum: 8, maximum: 72 }, if: -> { password.present? }
  validate :password_cannot_be_same_as_current, if: -> { password.present? && persisted? }

  # Fullname is set during signup
  validates :fullname, length: { maximum: 255 }, if: :fullname?

  # Handle validations
  # Handle is only required after email confirmation (allows user creation during registration)
  validates :handle, presence: true, if: :email_confirmed?
  # Other handle validations only apply when handle is present
  validates :handle,
    uniqueness: { case_sensitive: false },
    length: { in: 3..25 },
    format: {
      with: /\A[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]\z/,
      message: "must start with a letter and contain only letters, numbers, and hyphens"
    },
    if: -> { handle.present? }

  # Validate no consecutive hyphens on handle
  validate :no_consecutive_hyphens, if: -> { handle.present? }

  # Check if user has completed handle setup
  def handle_setup_complete?
    handle.present?
  end

  # Validate email
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validate :email_format

  # And normalize before saving
  before_save { self.email = email.downcase.strip }

  # ====================
  # Associations
  # ====================

  # Delete all subscriptions when the user is deleted
  has_many :subscriptions, dependent: :destroy
  # Get all websites through the subscriptions
  has_many :websites, through: :subscriptions
  # Delete all reading states when the user is deleted
  has_many :user_articles, dependent: :destroy
  # Delete all tags when the user is deleted
  has_many :tags, dependent: :destroy
  # Delete all lists when the user is deleted
  has_many :lists, dependent: :destroy

  # Create default lists for new users
  after_create :create_default_lists

  scope :admins, -> { where(admin: true) }
  scope :confirmed, -> { where.not(email_confirmed_at: nil) }
  scope :unconfirmed, -> { where(email_confirmed_at: nil) }

  # ====================
  # Constants
  # ====================

  DEFAULT_READING_SETTINGS = {
    "font_size" => "base",
    "font_family" => "sans",
    "theme" => "system",
    "content_width" => "default"
  }.freeze

  VALID_FONT_SIZES = %w[sm base lg xl].freeze
  VALID_FONT_FAMILIES = %w[sans serif mono].freeze
  VALID_THEMES = %w[system light dark].freeze
  VALID_CONTENT_WIDTHS = %w[narrow default wide].freeze
  VALID_HOME_TABS = %w[recent reading].freeze
  DEFAULT_HOME_TAB = "recent".freeze

  # Get the user's Read Next list
  def read_next_list
    lists.find_by(user_id: id, slug: List::READ_NEXT_SLUG)
  end

  # Get user-created reading lists (excludes system lists like Read Next)
  def reading_lists(order: :title)
    lists.user_lists.order(order)
  end

  def has_article?(article)
    user_articles.exists?(user: self, article: article)
  end

  def reading_settings
    DEFAULT_READING_SETTINGS.merge(settings["reading"] || {})
  end

  def update_reading_settings(new_settings)
    sanitized = {}
    sanitized["font_size"] = new_settings["font_size"] if VALID_FONT_SIZES.include?(new_settings["font_size"])
    sanitized["font_family"] = new_settings["font_family"] if VALID_FONT_FAMILIES.include?(new_settings["font_family"])
    sanitized["theme"] = new_settings["theme"] if VALID_THEMES.include?(new_settings["theme"])
    sanitized["content_width"] = new_settings["content_width"] if VALID_CONTENT_WIDTHS.include?(new_settings["content_width"])

    self.settings = settings.merge("reading" => reading_settings.merge(sanitized))
    save
  end

  def unread_articles
    Article.joins(:website)
           .where(websites: { id: website_ids })
           .where.not(id: removed_article_ids)
           .where.not(id: read_article_ids)
  end

  def unread_articles_for_website(website)
    website.articles
           .where.not(id: removed_article_ids)
           .where.not(id: read_article_ids)
           .order(publication_date: :desc)
  end

  def reading_articles
    Article.joins(:user_articles)
           .where(user_articles: {
             user_id: id,
             read_at: nil,
             removed_at: nil
           })
           .where(website_id: website_ids)
           .order("user_articles.updated_at DESC")
  end

  def home_tab_preference
    tab = settings["home_tab"]
    VALID_HOME_TABS.include?(tab) ? tab : DEFAULT_HOME_TAB
  end

  def update_home_tab_preference(tab)
    return false unless VALID_HOME_TABS.include?(tab)

    self.settings = settings.merge("home_tab" => tab)
    save
  end

  def admin?
    admin
  end

  def email_confirmed?
    email_confirmed_at.present?
  end

  def unconfirmed_email?
    unconfirmed_email.present?
  end

  # Record that a confirmation email was just sent. The token itself is generated
  # on the fly via generate_token_for(:email_confirmation); this timestamp only
  # drives the resend rate-limiting and the "link expired" message.
  #
  # Uses update_columns to bypass validations - this avoids issues with password
  # validation when the password is still in memory after user creation.
  def track_confirmation_sent
    sent_at = Time.current

    unless update_columns(email_confirmation_sent_at: sent_at)
      raise ActiveRecord::RecordNotSaved.new("Failed to record confirmation send", self)
    end

    self.email_confirmation_sent_at = sent_at
  end

  def confirm_email!
    attrs = {
      email_confirmed_at: Time.current
    }

    if unconfirmed_email?
      attrs[:email] = unconfirmed_email
      attrs[:unconfirmed_email] = nil
    end

    # Use update_columns to bypass validations - this avoids issues with
    # password validation when the password is still in memory
    update_columns(attrs)

    # Update the in-memory attributes to match
    attrs.each { |key, value| self[key] = value }
  end

  # Add user subscription to the website and start the processing job
  def subscribe_to_url(raw_url)
    normalized = UrlUtils.validate_and_normalize_url(raw_url)
    domain = UrlUtils.extract_domain(normalized)

    # Only block re-subscription for all websites
    if subscriptions.where(website_id: Website.where(domain:)).exists?
      raise AlreadySubscribedError, "You are already subscribed to #{domain}"
    end

    website = Website.where(domain:).first

    if website.nil?
      # Create a new website only if it's a new domain
      Website.transaction do
        website = Website.find_or_create_by!(domain:) do |w|
          w.name = domain
          w.processing_status = "pending"
        end

        ProcessWebsiteJob.perform_later(normalized)
      end

    elsif website.processing_status == "failed" || (website.articles.none? && !website.processing?)
      # Re-process a previously failed website, or an existing website that never got articles
      website.update!(processing_status: "pending")
      ProcessWebsiteJob.perform_later(normalized)
    end

    subscriptions.find_or_create_by!(website:)
    website
  end

  private
    def read_article_ids
      user_articles.read.select(:article_id)
    end

    def removed_article_ids
      user_articles.removed.select(:article_id)
    end

    def password_cannot_be_same_as_current
      return unless password.present?
      return unless persisted? && password_digest_was.present?

      old_password_digest = password_digest_was
      if BCrypt::Password.new(old_password_digest) == password
        errors.add(:password, "cannot be the same as your current password")
      end
    end

    def no_consecutive_hyphens
      if handle.present? && handle.include?("--")
        errors.add(:handle, "cannot contain consecutive hyphens")
      end
    end

    def email_format
      return if email.blank?

      URI::MailTo::EMAIL_REGEXP.match?(email) ||
        errors.add(:email, "must be a valid email address")
    end

    def create_default_lists
      List.create_read_next_for(self)
    end
end
