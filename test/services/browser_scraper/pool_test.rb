require "test_helper"

class BrowserScraper::PoolTest < ActiveSupport::TestCase
  test "with_scraper yields a BrowserScraper instance" do
    BrowserScraper::Pool.with_scraper do |scraper|
      assert scraper.is_a?(BrowserScraper)
    end
  end

  test "with_scraper reuses the same instance on the same thread" do
    scraper1 = nil
    scraper2 = nil
    
    BrowserScraper::Pool.with_scraper do |scraper|
      scraper1 = scraper
    end
    
    BrowserScraper::Pool.with_scraper do |scraper|
      scraper2 = scraper
    end
    
    assert_equal scraper1, scraper2
  end

  test "reset is called on the scraper between successive uses" do
    reset_calls = 0

    BrowserScraper::Pool.with_scraper do |scraper|
      # Patch reset on this specific instance to track calls
      scraper.define_singleton_method(:reset) { reset_calls += 1 }
    end

    assert_equal 1, reset_calls, "reset should be called after the first use"

    BrowserScraper::Pool.with_scraper do |scraper|
      # Second block — reset will be called again after this
    end

    assert_equal 2, reset_calls, "reset should be called after the second use"
  end

  test "a BrowserCrashedError discards the scraper and produces a fresh instance on next call" do
    first_scraper = nil
    second_scraper = nil
    cleanup_called = false

    # Capture the first instance and track force_cleanup
    BrowserScraper::Pool.with_scraper do |scraper|
      first_scraper = scraper
      first_scraper.define_singleton_method(:force_cleanup) { cleanup_called = true }
      first_scraper.instance_variable_set(:@crashed, true)
      raise BrowserScraper::BrowserCrashedError
    end rescue BrowserScraper::BrowserCrashedError

    BrowserScraper::Pool.with_scraper do |scraper|
      second_scraper = scraper
    end

    assert cleanup_called, "force_cleanup should have been called on the crashed scraper"
    assert_not_equal first_scraper, second_scraper, "a new instance should be created after a crash"
  end

  test "when fetch_count reaches MAX_FETCHES_BEFORE_RECYCLE, the next call produces a different instance" do
    first_scraper = nil
    second_scraper = nil

    BrowserScraper::Pool.with_scraper do |scraper|
      first_scraper = scraper
      scraper.instance_variable_set(:@fetch_count, BrowserScraper::MAX_FETCHES_BEFORE_RECYCLE)
    end

    BrowserScraper::Pool.with_scraper do |scraper|
      second_scraper = scraper
    end

    assert_not_equal first_scraper, second_scraper, "a new instance should be created after reaching max fetches"
  end

  test "when age exceeds MAX_AGE_BEFORE_RECYCLE, the next call produces a different instance" do
    first_scraper = nil
    second_scraper = nil

    BrowserScraper::Pool.with_scraper do |scraper|
      first_scraper = scraper
      scraper.instance_variable_set(:@started_at, Time.current - BrowserScraper::MAX_AGE_BEFORE_RECYCLE - 1)
    end

    BrowserScraper::Pool.with_scraper do |scraper|
      second_scraper = scraper
    end

    assert_not_equal first_scraper, second_scraper, "a new instance should be created after exceeding max age"
  end

  test "shutdown_current_thread calls quit and clears the thread-local" do
    first_scraper = nil
    second_scraper = nil
    quit_called = false

    BrowserScraper::Pool.with_scraper do |scraper|
      first_scraper = scraper
      first_scraper.define_singleton_method(:quit) { quit_called = true }
    end

    BrowserScraper::Pool.shutdown_current_thread

    BrowserScraper::Pool.with_scraper do |scraper|
      second_scraper = scraper
    end

    assert_not_equal first_scraper, second_scraper, "a new instance should be created after shutdown"
    assert quit_called, "quit should have been called on the first scraper"
  end

  test "shutdown_current_thread quits the scraper and clears the thread-local" do
    quit_called = false

    BrowserScraper::Pool.with_scraper do |scraper|
      scraper.define_singleton_method(:quit) { quit_called = true }
    end

    BrowserScraper::Pool.shutdown_current_thread

    assert quit_called
    assert_nil Thread.current[:browser_scraper]
  end
end