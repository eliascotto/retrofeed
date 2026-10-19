unless Rails.env.development?
  puts "WARN: Seed is only for development"
else
  def create_admin
    # =============================================================================
    # Admin User
    # =============================================================================
    # Creates the admin user for login access during screenshots.

    admin_user = User.find_or_create_by!(email: "admin@retrofeed.com") do |user|
      user.handle                = "admin"
      user.password              = "password123"
      user.password_confirmation = "password123"
      user.admin                 = true
      user.email_confirmed_at    = Time.current
    end

    if admin_user.handle.blank?
      admin_user.update!(handle: "admin")
    end

    puts "  Created admin user: admin@retrofeed.com"
  end

  create_admin
  if ENV["SEED_GENERATED_ARTICLES"]
    puts ""
    puts "=== Loading mock seeds ==="
    load Rails.root.join("db/seeds_mock.rb")
  end
end
