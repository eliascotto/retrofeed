# End-to-end tests using Playwright
# Runs the Rails server with the test database and executes Playwright tests

namespace :test do
  desc "Run end-to-end tests with Playwright"
  task e2e: :environment do
    require "socket"

    port = ENV.fetch("E2E_PORT", 3001)
    extractor_port = ENV.fetch("E2E_EXTRACTOR_PORT", 3881)

    puts "Preparing test databases..."
    system("RAILS_ENV=test bin/rails db:prepare") || abort("Failed to prepare test database")

    puts "Loading fixtures..."
    system("RAILS_ENV=test bin/rails db:fixtures:load") || abort("Failed to load fixtures")

    pids = []

    # Start the Rails server in test environment with Solid Queue enabled
    # SOLID_QUEUE_IN_PUMA=1 runs the job worker inside the Puma process
    # E2E_MOCK_DATA=true enables fixture-based mocking for web requests
    puts "Starting Rails server on port #{port} with test database and Solid Queue..."
    rails_pid = spawn(
      { "RAILS_ENV" => "test", "PORT" => port.to_s, "SOLID_QUEUE_IN_PUMA" => "1", "EXTRACTOR_PORT" => extractor_port.to_s, "E2E_MOCK_DATA" => "true" },
      "bin/rails", "server", "-b", "0.0.0.0", "-p", port.to_s,
      out: "/dev/null", err: "/dev/null"
    )
    pids << rails_pid

    # Start the node extractor service
    puts "Starting node extractor service on port #{extractor_port}..."
    node_pid = spawn(
      { "EXTRACTOR_PORT" => extractor_port.to_s },
      "node", "node_scripts/extractor.js",
      out: "/dev/null", err: "/dev/null"
    )
    pids << node_pid

    # Wait for server to be fully ready (not just TCP, but Rails app loaded)
    require "net/http"
    puts "Waiting for server to be ready..."
    max_attempts = 60
    attempts = 0
    loop do
      attempts += 1
      if attempts > max_attempts
        pids.each { |pid| Process.kill("TERM", pid) rescue nil }
        abort "Server failed to start within #{max_attempts} seconds"
      end

      begin
        # Check that the app is fully loaded by making an HTTP request to the health endpoint
        uri = URI("http://127.0.0.1:#{port}/up")
        response = Net::HTTP.get_response(uri)
        if response.code.to_i == 200
          break
        else
          sleep 1
        end
      rescue StandardError
        sleep 1
      end
    end
    puts "Server is ready!"

    # Run Playwright tests
    puts "Running Playwright tests..."
    system({ "E2E_PORT" => port.to_s }, "npx playwright test")
    test_exit_status = $?.exitstatus

    # Cleanup: kill the servers
    puts "Stopping servers..."
    pids.each do |pid|
      Process.kill("TERM", pid) rescue nil
      Process.wait(pid) rescue nil
    end

    exit test_exit_status
  end
end
