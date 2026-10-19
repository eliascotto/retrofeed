namespace :users do
  desc "List users"
  task list: :environment do
    puts "Users:"
    puts "=" * 60
    User.all.each do |user|
      puts "  - #{user.id} #{user.handle} #{user.email}"
    end
    puts "=" * 60
  end

  desc "Show single user"
  task :show, [ :id ] => :environment do |t, args|
    unless args[:id]
      puts "Usage:"
      puts "  bin/rake users:show[1]"
      puts "  bin/rails 'users:show[1]'  (for zsh)"
      puts "  bin/rails users:show\\[1\\]  (for zsh)"
      puts ""
      puts "Example:"
      puts "  bin/rake users:show[1]"
      next
    end
    id = args[:id]
    user = User.find(id)
    unless user
      puts "User not found with id: #{id}"
      puts "Available users:"
      User.all.each do |u|
        puts "  - #{u.id} #{u.handle} #{u.email}"
      end
      next
    end
    puts "User #{args[:id]} #{user.handle} #{user.email}"
    puts "=" * 60
  end
end
