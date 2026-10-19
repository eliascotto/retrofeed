require "test_helper"

class UrlUtilsResolveUrlTest < ActiveSupport::TestCase
  def resolve(url, base)
    UrlUtils.resolve_url(url, base)
  end

  BASE = "https://example.com"

  # ---------------------------------------------------------------------------
  # Nil / blank guards
  # ---------------------------------------------------------------------------

  test "returns nil when url is nil" do
    assert_nil resolve(nil, BASE)
  end

  test "returns nil when url is blank" do
    assert_nil resolve("", BASE)
    assert_nil resolve("   ", BASE)
  end

  test "returns nil when base_url is nil" do
    assert_nil resolve("/about", nil)
  end

  test "returns nil when base_url is blank" do
    assert_nil resolve("/about", "")
    assert_nil resolve("/about", "   ")
  end

  # ---------------------------------------------------------------------------
  # Already-absolute URLs
  # ---------------------------------------------------------------------------

  test "returns an https URL unchanged" do
    assert_equal "https://other.com/page", resolve("https://other.com/page", BASE)
  end

  test "returns an http URL unchanged" do
    assert_equal "http://other.com/page", resolve("http://other.com/page", BASE)
  end

  test "returns nil for non-http schemes" do
    assert_nil resolve("ftp://files.example.com/data", BASE)
    assert_nil resolve("mailto:user@example.com", BASE)
    assert_nil resolve("javascript:void(0)", BASE)
  end

  test "normalizes an absolute URL with dot segments" do
    assert_equal "https://other.com/a/c",
                 resolve("https://other.com/a/b/../c", BASE)
  end

  # ---------------------------------------------------------------------------
  # Root-relative paths (start with /)
  # ---------------------------------------------------------------------------

  test "resolves root-relative path against base scheme and host" do
    assert_equal "https://example.com/about",
                 resolve("/about", BASE)
  end

  test "resolves root-relative path ignoring base path" do
    assert_equal "https://example.com/about",
                 resolve("/about", "https://example.com/blog/post")
  end

  test "preserves deep root-relative paths" do
    assert_equal "https://example.com/a/b/c",
                 resolve("/a/b/c", BASE)
  end

  test "resolves root slash to origin" do
    assert_equal "https://example.com/",
                 resolve("/", "https://example.com/blog")
  end

  test "resolves root-relative path against a base with a port" do
    assert_equal "https://example.com:8080/about",
                 resolve("/about", "https://example.com:8080/blog")
  end

  # ---------------------------------------------------------------------------
  # Bare relative paths — directory heuristic
  #
  # When the base path has no trailing slash and no file extension,
  # the method treats it as a directory to avoid stripping the last segment.
  # ---------------------------------------------------------------------------

  test "resolves bare relative path against an extension-less base path (treated as directory)" do
    assert_equal "https://example.com/blog/pcall.html",
                 resolve("pcall.html", "https://example.com/blog")
  end

  test "resolves bare relative path when base already ends with a slash" do
    assert_equal "https://example.com/blog/pcall.html",
                 resolve("pcall.html", "https://example.com/blog/")
  end

  test "resolves bare relative path against a base that ends with a file (extension present)" do
    # Base has extension → standard resolution strips the last segment
    assert_equal "https://example.com/blog/pcall.html",
                 resolve("pcall.html", "https://example.com/blog/post.html")
  end

  test "resolves nested bare relative path" do
    assert_equal "https://example.com/blog/nested/page.html",
                 resolve("nested/page.html", "https://example.com/blog")
  end

  test "resolves dot-dot relative path against a directory base" do
    assert_equal "https://example.com/other.html",
                 resolve("../other.html", "https://example.com/blog/")
  end

  test "resolves dot-dot relative path against a file base" do
    assert_equal "https://example.com/other.html",
                 resolve("../other.html", "https://example.com/blog/post.html")
  end

  test "resolves current-directory relative path" do
    assert_equal "https://example.com/blog/page.html",
                 resolve("./page.html", "https://example.com/blog/")
  end

  test "resolves relative path from root base" do
    assert_equal "https://example.com/page.html",
                 resolve("page.html", BASE)
  end

  # ---------------------------------------------------------------------------
  # URL normalization
  # ---------------------------------------------------------------------------

  test "trims leading and trailing whitespace from url" do
    assert_equal "https://example.com/about",
                 resolve("  /about  ", BASE)
  end
end
