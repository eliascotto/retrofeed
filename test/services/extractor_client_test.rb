require "test_helper"

class ExtractorClientTest < ActiveSupport::TestCase
  setup do
    ExtractorClient.reset_connection!
  end

  teardown do
    ExtractorClient.reset_connection!
  end

  test "extract returns content hash on success" do
    stub_extractor_response(200, {
      url: "https://example.com/article",
      title: "Test Article",
      contentHtml: "<p>Content</p>",
      contentMd: "Content",
      wordCount: 10
    })

    result = ExtractorClient.extract(url: "https://example.com/article")

    assert_equal "Test Article", result[:title]
    assert_equal "<p>Content</p>", result[:contentHtml]
    assert_equal "Content", result[:contentMd]
    assert_equal 10, result[:wordCount]
  end

  test "extract with html passes html in request body" do
    stub_request(:post, "http://localhost:3880/extract")
      .with(body: { url: "https://example.com", html: "<html>test</html>" }.to_json)
      .to_return(status: 200, body: { title: "Test" }.to_json)

    result = ExtractorClient.extract(url: "https://example.com", html: "<html>test</html>")

    assert_equal "Test", result[:title]
  end

  test "extract returns error hash on extraction failure" do
    stub_extractor_response(200, { error: "Failed to extract" })

    result = ExtractorClient.extract(url: "https://example.com/article")

    assert_equal "Failed to extract", result[:error]
  end

  test "extract returns error on bad request" do
    stub_extractor_response(400, { error: "Invalid JSON" })

    result = ExtractorClient.extract(url: "https://example.com/article")

    assert_equal "Invalid JSON", result[:error]
  end

  test "extract raises ConnectionError when server unavailable" do
    stub_request(:post, "http://localhost:3880/extract")
      .to_raise(Errno::ECONNREFUSED)

    assert_raises(ExtractorClient::ConnectionError) do
      ExtractorClient.extract(url: "https://example.com/article")
    end
  end

  test "extract raises TimeoutError on read timeout" do
    stub_request(:post, "http://localhost:3880/extract")
      .to_timeout

    assert_raises(ExtractorClient::TimeoutError) do
      ExtractorClient.extract(url: "https://example.com/article")
    end
  end

  test "health returns server status" do
    stub_request(:get, "http://localhost:3880/health")
      .to_return(status: 200, body: { status: "ok", uptime: 123.45 }.to_json)

    result = ExtractorClient.health

    assert_equal "ok", result[:status]
    assert_equal 123.45, result[:uptime]
  end

  test "available? returns true when server responds" do
    stub_request(:get, "http://localhost:3880/health")
      .to_return(status: 200, body: { status: "ok" }.to_json)

    assert ExtractorClient.available?
  end

  test "available? returns false when server unavailable" do
    stub_request(:get, "http://localhost:3880/health")
      .to_raise(Errno::ECONNREFUSED)

    assert_not ExtractorClient.available?
  end

  test "reconnects automatically after connection reset" do
    # First request fails with connection reset
    stub_request(:post, "http://localhost:3880/extract")
      .to_raise(Errno::ECONNRESET).then
      .to_return(status: 200, body: { title: "Test" }.to_json)

    result = ExtractorClient.extract(url: "https://example.com/article")

    assert_equal "Test", result[:title]
  end

  test "concurrent requests from different threads use separate connections" do
    # This test verifies that thread-local connections work correctly
    # by running concurrent requests without HTTP connection corruption.
    stub_request(:post, "http://localhost:3880/extract")
      .to_return(status: 200, body: { title: "Test", wordCount: 100 }.to_json)

    results = []
    mutex = Mutex.new
    errors = []

    # Run 5 concurrent threads, each making a request
    threads = 5.times.map do |i|
      Thread.new do
        begin
          result = ExtractorClient.extract(url: "https://example.com/article#{i}")
          mutex.synchronize { results << result }
        rescue => e
          mutex.synchronize { errors << e }
        end
      end
    end

    threads.each(&:join)

    assert_empty errors, "Expected no errors but got: #{errors.map(&:message).join(', ')}"
    assert_equal 5, results.length, "Expected 5 results but got #{results.length}"
    results.each do |result|
      assert_equal "Test", result[:title]
      assert_equal 100, result[:wordCount]
    end
  end

  private

  def stub_extractor_response(status, body)
    stub_request(:post, "http://localhost:3880/extract")
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end
end
