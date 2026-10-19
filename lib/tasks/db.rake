# frozen_string_literal: true

namespace :db do
  namespace :seed do
    desc "Reset database and load mock data for presentation screenshots"
    task mock: :environment do
      puts "=== Resetting database ==="
      Rake::Task["db:reset"].invoke

      puts ""
      puts "=== Loading mock seeds ==="
      load Rails.root.join("db/seeds_mock.rb")
    end
  end
end
