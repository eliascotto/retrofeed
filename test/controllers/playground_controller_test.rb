require "test_helper"

class PlaygroundControllerTest < ActionDispatch::IntegrationTest
  ARCHIVE_HTML = <<~HTML
    <html>
      <body>
        <article><a href="/posts/one">Post One</a><time>2024-01-01</time></article>
        <article><a href="/posts/two">Post Two</a><time>2024-01-02</time></article>
        <article><a href="/posts/three">Post Three</a><time>2024-01-03</time></article>
      </body>
    </html>
  HTML

  setup do
    @archive_url = "https://example.com/blog"

    @fetch_result = {
      content: ARCHIVE_HTML,
      html: ARCHIVE_HTML,
      source: :fixture,
      fetched_at: Time.current.iso8601,
      fetcher_type: "live",
      final_url: @archive_url
    }

    @detection_result = Struct.new(:url, :method, :confidence_score, :pagination_detected, :notes).new(
      @archive_url, "link_analysis", 0.85, false, "Found via link analysis"
    )
  end

  test "show renders form without params" do
    get playground_path
    assert_response :success
  end

  test "show with website param processes URL and renders results" do
    detector_double = Object.new
    detector_double.define_singleton_method(:detect) { @detection_result }

    stub_singleton(WebFetcher::Playground, :fetch, @fetch_result) do
      stub_singleton(ArchivePageDetector, :new, detector_double) do
        get playground_path(website: "https://example.com")
        assert_response :success
        assert_select "h1", text: /Results for/
      end
    end
  end

  test "debug mode renders the phase comparison and container candidate tables" do
    detection_result = @detection_result
    detector_double = Object.new
    detector_double.define_singleton_method(:detect) { detection_result }

    stub_singleton(WebFetcher::Playground, :fetch, @fetch_result) do
      stub_singleton(ArchivePageDetector, :new, detector_double) do
        get playground_path(website: "https://example.com", debug: "1")
        assert_response :success
        assert_select "h4", text: /Phase Comparison/
        assert_select "h4", text: /Container Candidates/
      end
    end
  end

  test "non-debug mode omits the phase comparison table" do
    detection_result = @detection_result
    detector_double = Object.new
    detector_double.define_singleton_method(:detect) { detection_result }

    stub_singleton(WebFetcher::Playground, :fetch, @fetch_result) do
      stub_singleton(ArchivePageDetector, :new, detector_double) do
        get playground_path(website: "https://example.com")
        assert_response :success
        assert_select "h4", text: /Phase Comparison/, count: 0
      end
    end
  end

  test "pages fetched includes all urls visited during detection" do
    detector_double = Object.new
    detection_result = @detection_result

    detector_double.define_singleton_method(:detect) do
      # Simulate the detector fetching the origin and two candidates before resolving
      if (log = Thread.current[:playground_fetch_log])
        log << { url: "https://example.com/", source: :fixture, size: 500, fetched_at: nil, fetcher_type: "live" }
        log << { url: "https://example.com/archive", source: :fixture, size: 800, fetched_at: nil, fetcher_type: "live" }
        log << { url: "https://example.com/blog", source: :fixture, size: 1200, fetched_at: nil, fetcher_type: "live" }
      end
      detection_result
    end

    stub_singleton(WebFetcher::Playground, :fetch, @fetch_result) do
      stub_singleton(ArchivePageDetector, :new, detector_double) do
        get playground_path(website: "https://example.com")
      end
    end

    assert_response :success
    # Three detection pages should appear in the pages table
    assert_select "#pages-fetched-table tbody tr", count: 3
  end

  test "archive page is marked with archive role badge" do
    detector_double = Object.new
    detection_result = @detection_result

    detector_double.define_singleton_method(:detect) do
      if (log = Thread.current[:playground_fetch_log])
        log << { url: "https://example.com/", source: :fixture, size: 500, fetched_at: nil, fetcher_type: "live" }
        log << { url: "https://example.com/blog", source: :fixture, size: 1200, fetched_at: nil, fetcher_type: "live" }
      end
      detection_result
    end

    stub_singleton(WebFetcher::Playground, :fetch, @fetch_result) do
      stub_singleton(ArchivePageDetector, :new, detector_double) do
        get playground_path(website: "https://example.com")
      end
    end

    assert_select ".badge", text: "archive"
  end

  test "non-archive detection pages are marked with probe role badge" do
    detector_double = Object.new
    detection_result = @detection_result

    detector_double.define_singleton_method(:detect) do
      if (log = Thread.current[:playground_fetch_log])
        log << { url: "https://example.com/", source: :fixture, size: 500, fetched_at: nil, fetcher_type: "live" }
        log << { url: "https://example.com/blog", source: :fixture, size: 1200, fetched_at: nil, fetcher_type: "live" }
      end
      detection_result
    end

    stub_singleton(WebFetcher::Playground, :fetch, @fetch_result) do
      stub_singleton(ArchivePageDetector, :new, detector_double) do
        get playground_path(website: "https://example.com")
      end
    end

    assert_select ".badge", text: "probe"
  end

  test "pages fetched is empty when no fetches occur during detection" do
    detector_double = Object.new
    detector_double.define_singleton_method(:detect) { @detection_result }

    stub_singleton(WebFetcher::Playground, :fetch, @fetch_result) do
      stub_singleton(ArchivePageDetector, :new, detector_double) do
        get playground_path(website: "https://example.com")
      end
    end

    assert_response :success
    # Fetch log is empty so the pages section should not be rendered
    assert_select "h2", text: /Pages Fetched/, count: 0
  end

  test "detection trace table renders decisions logged during detection" do
    detector_double = Object.new
    detection_result = @detection_result

    detector_double.define_singleton_method(:detect) do
      if (log = Thread.current[:playground_detection_log])
        log << { strategy: "user_provided", candidate_url: "https://example.com/", accepted: false, reason: "User provided homepage; checking known paths first", score: nil }
        log << { strategy: "link_analysis", candidate_url: "https://example.com/blog", accepted: true, reason: "Best candidate via link analysis", score: 0.85 }
      end
      detection_result
    end

    stub_singleton(WebFetcher::Playground, :fetch, @fetch_result) do
      stub_singleton(ArchivePageDetector, :new, detector_double) do
        get playground_path(website: "https://example.com")
      end
    end

    assert_response :success
    assert_select "#detection-trace-table tbody tr", count: 2
    assert_select "#detection-trace-table .badge", text: "accepted"
    assert_select "#detection-trace-table .badge", text: "rejected"
  end
end
