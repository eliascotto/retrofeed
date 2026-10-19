require "test_helper"

class ErrorReporterTest < ActiveSupport::TestCase
  setup do
    ContentErrorGroup.delete_all
  end

  test "creates a grouped error with context and increments occurrences" do
    error = WebFetcher::FetchError.new(
      "HTTP 500 while fetching https://example.com/a",
      http_status: 500,
      headers: { "Content-Type" => "text/html" },
      url: "https://example.com/a"
    )

    assert_difference -> { ContentErrorGroup.count }, +1 do
      ErrorReporter.record(
        phase: "fetch",
        operation: "website_archive_fetch",
        message: error.message,
        exception: error,
        url: error.url
      )
    end

    first = ContentErrorGroup.last
    assert_equal 1, first.occurrences_count
    assert_equal "example.com", first.domain
    assert_equal 500, first.http_status
    assert_equal "website_archive_fetch", first.operation

    travel 1.minute do
      assert_no_difference -> { ContentErrorGroup.count } do
        ErrorReporter.record(
          phase: "fetch",
          operation: "website_archive_fetch",
          message: error.message,
          exception: error,
          url: error.url
        )
      end
    end

    first.reload
    assert_equal 2, first.occurrences_count
    assert first.last_seen_at > first.first_seen_at
  end
end
