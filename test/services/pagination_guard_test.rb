require "test_helper"

class PaginationGuardTest < ActiveSupport::TestCase
  setup do
    @guard = PaginationGuard.new
  end

  test "allows first page to continue" do
    result = @guard.safe_to_continue?(
      page_url: "https://example.com/blog",
      page_number: 1,
      content_fingerprint: "abc123",
      discovered_posts: [ "https://example.com/post-1", "https://example.com/post-2" ]
    )

    assert result
    assert_not @guard.halted?
    assert_nil @guard.halt_reason
  end

  test "halts on circular URL" do
    @guard.safe_to_continue?(
      page_url: "https://example.com/blog",
      page_number: 1,
      content_fingerprint: "fp1",
      discovered_posts: [ "https://example.com/post-1" ]
    )

    result = @guard.safe_to_continue?(
      page_url: "https://example.com/blog",
      page_number: 2,
      content_fingerprint: "fp2",
      discovered_posts: [ "https://example.com/post-2" ]
    )

    assert_not result
    assert @guard.halted?
    assert_equal :circular_url, @guard.halt_reason
    assert_match(/Already visited/, @guard.halt_subreason)
  end

  test "halts on duplicate content fingerprint" do
    fingerprint = "same_fingerprint"

    @guard.safe_to_continue?(
      page_url: "https://example.com/blog/page/1",
      page_number: 1,
      content_fingerprint: fingerprint,
      discovered_posts: [ "https://example.com/post-1" ]
    )

    result = @guard.safe_to_continue?(
      page_url: "https://example.com/blog/page/2",
      page_number: 2,
      content_fingerprint: fingerprint,
      discovered_posts: [ "https://example.com/post-1" ]
    )

    assert_not result
    assert @guard.halted?
    assert_equal :duplicate_content, @guard.halt_reason
  end

  test "halts after max consecutive empty pages" do
    guard = PaginationGuard.new(max_consecutive_empty: 3)

    # First two empty pages are OK
    result1 = guard.safe_to_continue?(
      page_url: "https://example.com/page/1",
      content_fingerprint: "fp1",
      discovered_posts: []
    )
    assert result1

    result2 = guard.safe_to_continue?(
      page_url: "https://example.com/page/2",
      content_fingerprint: "fp2",
      discovered_posts: []
    )
    assert result2

    # Third empty page halts
    result3 = guard.safe_to_continue?(
      page_url: "https://example.com/page/3",
      content_fingerprint: "fp3",
      discovered_posts: []
    )
    assert_not result3
    assert guard.halted?
    assert_equal :empty_pages, guard.halt_reason
  end

  test "resets empty page counter when posts are found" do
    guard = PaginationGuard.new(max_consecutive_empty: 3)

    # Two empty pages
    guard.safe_to_continue?(page_url: "p1", content_fingerprint: "fp1", discovered_posts: [])
    guard.safe_to_continue?(page_url: "p2", content_fingerprint: "fp2", discovered_posts: [])

    # Page with posts resets counter
    guard.safe_to_continue?(page_url: "p3", content_fingerprint: "fp3", discovered_posts: [ "post1" ])

    # Two more empty pages should be OK
    result = guard.safe_to_continue?(page_url: "p4", content_fingerprint: "fp4", discovered_posts: [])
    assert result
    result = guard.safe_to_continue?(page_url: "p5", content_fingerprint: "fp5", discovered_posts: [])
    assert result

    # Third empty page after reset halts
    result = guard.safe_to_continue?(page_url: "p6", content_fingerprint: "fp6", discovered_posts: [])
    assert_not result
    assert_equal :empty_pages, guard.halt_reason
  end

  test "halts on duplicate posts streak" do
    guard = PaginationGuard.new(max_duplicate_streak: 3)

    # First page with unique posts
    guard.safe_to_continue?(
      page_url: "p1",
      content_fingerprint: "fp1",
      discovered_posts: [ "post1", "post2" ]
    )

    # Pages with all duplicate posts
    guard.safe_to_continue?(
      page_url: "p2",
      content_fingerprint: "fp2",
      discovered_posts: [ "post1" ]  # duplicate
    )
    guard.safe_to_continue?(
      page_url: "p3",
      content_fingerprint: "fp3",
      discovered_posts: [ "post2" ]  # duplicate
    )
    result = guard.safe_to_continue?(
      page_url: "p4",
      content_fingerprint: "fp4",
      discovered_posts: [ "post1", "post2" ]  # all duplicates
    )

    assert_not result
    assert_equal :circular_pagination, guard.halt_reason
  end

  test "resets duplicate streak when new posts found" do
    guard = PaginationGuard.new(max_duplicate_streak: 3)

    guard.safe_to_continue?(page_url: "p1", content_fingerprint: "fp1", discovered_posts: [ "post1" ])
    guard.safe_to_continue?(page_url: "p2", content_fingerprint: "fp2", discovered_posts: [ "post1" ]) # dup
    guard.safe_to_continue?(page_url: "p3", content_fingerprint: "fp3", discovered_posts: [ "post1" ]) # dup

    # New post resets counter
    guard.safe_to_continue?(page_url: "p4", content_fingerprint: "fp4", discovered_posts: [ "post2" ])

    # Two more dup pages should be OK
    result = guard.safe_to_continue?(page_url: "p5", content_fingerprint: "fp5", discovered_posts: [ "post1" ])
    assert result
    result = guard.safe_to_continue?(page_url: "p6", content_fingerprint: "fp6", discovered_posts: [ "post2" ])
    assert result

    # Third dup page halts
    result = guard.safe_to_continue?(page_url: "p7", content_fingerprint: "fp7", discovered_posts: [ "post1" ])
    assert_not result
    assert_equal :circular_pagination, guard.halt_reason
  end

  test "halts on page number jump" do
    guard = PaginationGuard.new(max_page_jump: 10)

    guard.safe_to_continue?(
      page_url: "p1",
      page_number: 1,
      content_fingerprint: "fp1",
      discovered_posts: [ "post1" ]
    )

    result = guard.safe_to_continue?(
      page_url: "p2",
      page_number: 100,  # jump of 99
      content_fingerprint: "fp2",
      discovered_posts: [ "post2" ]
    )

    assert_not result
    assert_equal :page_jump, guard.halt_reason
    assert_match(/exceeds max/, guard.halt_subreason)
  end

  test "allows normal page progression" do
    guard = PaginationGuard.new(max_page_jump: 10)

    (1..5).each do |n|
      result = guard.safe_to_continue?(
        page_url: "p#{n}",
        page_number: n,
        content_fingerprint: "fp#{n}",
        discovered_posts: [ "post#{n}" ]
      )
      assert result, "Page #{n} should be allowed"
    end

    assert_not guard.halted?
  end

  test "tracks total posts discovered" do
    @guard.safe_to_continue?(
      page_url: "p1",
      content_fingerprint: "fp1",
      discovered_posts: [ "post1", "post2" ]
    )
    @guard.safe_to_continue?(
      page_url: "p2",
      content_fingerprint: "fp2",
      discovered_posts: [ "post3", "post1" ]  # post1 is duplicate
    )

    assert_equal 3, @guard.total_posts_discovered
  end

  test "tracks total pages visited" do
    @guard.safe_to_continue?(page_url: "p1", content_fingerprint: "fp1", discovered_posts: [])
    @guard.safe_to_continue?(page_url: "p2", content_fingerprint: "fp2", discovered_posts: [])
    @guard.safe_to_continue?(page_url: "p3", content_fingerprint: "fp3", discovered_posts: [])

    assert_equal 3, @guard.total_pages_visited
  end

  test "generate_fingerprint creates consistent hash" do
    fp1 = PaginationGuard.generate_fingerprint("https://example.com/page/1", [ "post1", "post2" ])
    fp2 = PaginationGuard.generate_fingerprint("https://example.com/page/1", [ "post2", "post1" ])
    fp3 = PaginationGuard.generate_fingerprint("https://example.com/page/2", [ "post1", "post2" ])

    # Same URL and posts (different order) should produce same fingerprint
    assert_equal fp1, fp2

    # Different URL should produce different fingerprint
    assert_not_equal fp1, fp3
  end

  test "stays halted once halted" do
    @guard.safe_to_continue?(
      page_url: "p1",
      content_fingerprint: "fp1",
      discovered_posts: []
    )
    @guard.safe_to_continue?(page_url: "p2", content_fingerprint: "fp2", discovered_posts: [])
    @guard.safe_to_continue?(page_url: "p3", content_fingerprint: "fp3", discovered_posts: [])

    # Now halted
    assert @guard.halted?

    # Should stay halted even with valid input
    result = @guard.safe_to_continue?(
      page_url: "p4",
      content_fingerprint: "fp4",
      discovered_posts: [ "post1" ]
    )

    assert_not result
    assert @guard.halted?
  end
end
