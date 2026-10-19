require "test_helper"

class FaviconDownloaderTest < ActiveSupport::TestCase
  setup do
    @website = Website.create!(domain: "test-download.com", name: "Test Site")
  end

  teardown do
    @website.favicon.purge if @website.favicon.attached?
    @website.destroy!
  end

  test "downloads and attaches favicon successfully" do
    # Create a simple PNG favicon (1x1 pixel)
    png_data = create_minimal_png
    stub_request(:get, "https://example.com/favicon.png").to_return(body: png_data, status: 200)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.png")

    assert result
    assert @website.favicon.attached?
    assert_equal "favicon.png", @website.favicon.filename.to_s
    assert_equal "image/png", @website.favicon.content_type
  end

  test "detects PNG content type from magic bytes" do
    png_data = create_minimal_png
    stub_request(:get, "https://example.com/icon").to_return(body: png_data, status: 200)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/icon")

    assert result
    assert_equal "image/png", @website.favicon.content_type
  end

  test "detects ICO content type from magic bytes" do
    # ICO magic bytes: 00 00 01 00
    ico_data = "\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00\x04\x00".dup.force_encoding("BINARY")
    stub_request(:get, "https://example.com/favicon.ico").to_return(body: ico_data, status: 200)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.ico")

    assert result
    # Accept either ICO content type (ActiveStorage may normalize)
    assert_includes [ "image/x-icon", "image/vnd.microsoft.icon" ], @website.favicon.content_type
  end

  test "detects GIF content type from magic bytes" do
    # GIF magic bytes: 47 49 46 38
    gif_data = "GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".dup.force_encoding("BINARY")
    stub_request(:get, "https://example.com/favicon.gif").to_return(body: gif_data, status: 200)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.gif")

    assert result
    assert_equal "image/gif", @website.favicon.content_type
  end

  test "detects JPEG content type from magic bytes" do
    # JPEG magic bytes: FF D8 FF
    jpeg_data = "\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00".dup.force_encoding("BINARY")
    stub_request(:get, "https://example.com/favicon.jpg").to_return(body: jpeg_data, status: 200)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.jpg")

    assert result
    assert_equal "image/jpeg", @website.favicon.content_type
  end

  test "detects SVG content type" do
    svg_data = '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>'
    stub_request(:get, "https://example.com/favicon.svg").to_return(body: svg_data, status: 200)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.svg")

    assert result
    assert_equal "image/svg+xml", @website.favicon.content_type
  end

  test "returns false for invalid URL" do
    result = FaviconDownloader.download_and_attach(@website, "")

    assert_not result
    assert_not @website.favicon.attached?
  end

  test "returns false for nil URL" do
    result = FaviconDownloader.download_and_attach(@website, nil)

    assert_not result
    assert_not @website.favicon.attached?
  end

  test "returns false when fetch fails with 404" do
    stub_request(:get, "https://example.com/favicon.ico").to_return(status: 404)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.ico")

    assert_not result
    assert_not @website.favicon.attached?
  end

  test "returns false when fetch times out" do
    stub_request(:get, "https://example.com/favicon.ico").to_timeout

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.ico")

    assert_not result
    assert_not @website.favicon.attached?
  end

  test "returns false when content is empty" do
    stub_request(:get, "https://example.com/favicon.ico").to_return(body: "", status: 200)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.ico")

    assert_not result
    assert_not @website.favicon.attached?
  end

  test "returns false when content is too large" do
    # Create content larger than MAX_FAVICON_SIZE (256KB)
    large_content = "x" * (257 * 1024)
    stub_request(:get, "https://example.com/favicon.ico").to_return(body: large_content, status: 200)

    result = FaviconDownloader.download_and_attach(@website, "https://example.com/favicon.ico")

    assert_not result
    assert_not @website.favicon.attached?
  end

  test "handles ftp:// URLs gracefully" do
    result = FaviconDownloader.download_and_attach(@website, "ftp://example.com/favicon.ico")

    assert_not result
    assert_not @website.favicon.attached?
  end

  private

  def create_minimal_png
    # Minimal 1x1 pixel PNG
    "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82".dup.force_encoding("BINARY")
  end
end
