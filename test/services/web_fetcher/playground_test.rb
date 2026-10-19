require "test_helper"

class WebFetcher::PlaygroundTest < ActiveSupport::TestCase
  FIXTURE_HTML = "<html><body>fixture content</body></html>"

  setup do
    @url = "https://example.com/blog"
    @tmpdir = Dir.mktmpdir
    @fixture_file = File.join(@tmpdir, "fixture.html")
    File.binwrite(@fixture_file, FIXTURE_HTML)
  end

  teardown do
    Thread.current[:playground_fetch_log] = nil
    FileUtils.rm_rf(@tmpdir)
  end

  test "fetch appends an entry to the log when log is initialized" do
    Thread.current[:playground_fetch_log] = []

    stub_singleton(Playground::FixtureCache, :find_fixture, @fixture_file) do
      stub_singleton(Playground::FixtureCache, :load_metadata, {
        fetched_at: "2024-01-01T00:00:00Z",
        final_url: @url,
        fetcher_type: "live",
        http_status: 200
      }) do
        WebFetcher::Playground.fetch(@url)
      end
    end

    assert_equal 1, Thread.current[:playground_fetch_log].length

    entry = Thread.current[:playground_fetch_log].first
    assert_equal @url, entry[:url]
    assert_equal :fixture, entry[:source]
    assert_equal FIXTURE_HTML.bytesize, entry[:size]
    assert_equal "2024-01-01T00:00:00Z", entry[:fetched_at]
    assert_equal "live", entry[:fetcher_type]
  end

  test "fetch does not modify the log when log is nil" do
    Thread.current[:playground_fetch_log] = nil

    stub_singleton(Playground::FixtureCache, :find_fixture, @fixture_file) do
      stub_singleton(Playground::FixtureCache, :load_metadata, { final_url: @url, fetcher_type: "live" }) do
        WebFetcher::Playground.fetch(@url)
      end
    end

    assert_nil Thread.current[:playground_fetch_log]
  end

  test "fetch accumulates an entry per call" do
    Thread.current[:playground_fetch_log] = []

    urls = ["https://example.com/", "https://example.com/archive", "https://example.com/blog"]

    urls.each do |url|
      stub_singleton(Playground::FixtureCache, :find_fixture, @fixture_file) do
        stub_singleton(Playground::FixtureCache, :load_metadata, { final_url: url, fetcher_type: "live" }) do
          WebFetcher::Playground.fetch(url)
        end
      end
    end

    assert_equal 3, Thread.current[:playground_fetch_log].length
    assert_equal urls, Thread.current[:playground_fetch_log].map { |e| e[:url] }
  end

  test "log entry uses final_url from the result rather than the requested url" do
    redirect_target = "https://example.com/blog/"
    Thread.current[:playground_fetch_log] = []

    stub_singleton(Playground::FixtureCache, :find_fixture, @fixture_file) do
      stub_singleton(Playground::FixtureCache, :load_metadata, {
        final_url: redirect_target,
        fetcher_type: "live"
      }) do
        WebFetcher::Playground.fetch(@url)
      end
    end

    assert_equal redirect_target, Thread.current[:playground_fetch_log].first[:url]
  end

  test "log entry records size in bytes" do
    Thread.current[:playground_fetch_log] = []

    stub_singleton(Playground::FixtureCache, :find_fixture, @fixture_file) do
      stub_singleton(Playground::FixtureCache, :load_metadata, { final_url: @url, fetcher_type: "live" }) do
        WebFetcher::Playground.fetch(@url)
      end
    end

    assert_equal FIXTURE_HTML.bytesize, Thread.current[:playground_fetch_log].first[:size]
  end
end
