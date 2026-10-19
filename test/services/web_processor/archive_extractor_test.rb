require "test_helper"

class WebProcessor::ArchiveContainerExtractorTest < ActiveSupport::TestCase
  BASE = "https://example.com"

  def doc(html) = Nokogiri::HTML(html)

  def extract(html, base: BASE)
    results = WebProcessor::ArchiveExtractor.extract_articles(doc(html), base)
    results.fetch(:articles, [])
  end

  def trace_for(html, base: BASE, debug: false)
    WebProcessor::ArchiveExtractor.extract_articles(doc(html), base, debug: debug).fetch(:trace)
  end

  # Repeats a block template, replacing every "%d" with the iteration number,
  # n times, joined into one string.
  def repeat(template, n, from: 1) = (from...(from + n)).map { |i| template.gsub("%d", i.to_s) }.join

  # ---------------------------------------------------------------------------
  # Group A: Phase 1 happy paths (fast CSS selectors)
  # ---------------------------------------------------------------------------

  test "extracts semantic article containers with heading links" do
    html = "<html><body>" + repeat(<<~ITEM, 3) + "</body></html>"
      <article><h2><a href="/posts/slug-%d">Title %d</a></h2></article>
    ITEM

    articles = extract(html)

    assert_equal 3, articles.length
    assert_equal %w[Title\ 1 Title\ 2 Title\ 3].sort, articles.map { |a| a[:title] }.sort
  end

  test "returns articles with the expected hash shape and absolute urls" do
    html = "<html><body>" + repeat(<<~ITEM, 3) + "</body></html>"
      <article><h2><a href="/posts/slug-%d">Title %d</a></h2></article>
    ITEM

    article = extract(html).first

    assert_equal %i[title url date tags].sort, article.keys.intersection(%i[title url date tags]).sort
    assert article[:url].start_with?("https://example.com/posts/")
    assert_kind_of Array, article[:tags]
  end

  test "extracts articles nested under main" do
    html = "<html><body><main>" + repeat(<<~ITEM, 3) + "</main></body></html>"
      <article><h2><a href="/posts/slug-%d">Title %d</a></h2></article>
    ITEM

    assert_equal 3, extract(html).length
  end

  test "extracts the link-as-container pattern where an anchor wraps a div" do
    html = "<html><body><main><div class=\"flex-col\">" +
      repeat(<<~ITEM, 3) + "</div></main></body></html>"
      <a href="/posts/slug-%d"><div><h3>Title %d</h3></div></a>
    ITEM

    articles = extract(html)

    assert_equal 3, articles.length
    assert articles.all? { |a| a[:url].start_with?("https://example.com/posts/") }
  end

  test "extracts list-item containers under ul.posts" do
    html = "<html><body><ul class=\"posts\">" +
      repeat(<<~ITEM, 3) + "</ul></body></html>"
      <li><a href="/blog/slug-%d">Title %d</a></li>
    ITEM

    assert_equal 3, extract(html).length
  end

  test "extracts table rows with title cells and dates from the url" do
    html = <<~HTML
      <html><body><table class="archive">
        <tr><td class="title"><a href="/2024/01/15/a">First</a></td></tr>
        <tr><td class="title"><a href="/2024/02/20/b">Second</a></td></tr>
        <tr><td class="title"><a href="/2024/03/25/c">Third</a></td></tr>
      </table></body></html>
    HTML

    articles = extract(html)

    assert_equal 3, articles.length
    first = articles.find { |a| a[:title] == "First" }
    assert_equal Date.new(2024, 1, 15), first[:date]
  end

  test "extracts table rows whose cells carry no title/date class (patshaughnessy-style)" do
    # Real-world archive (patshaughnessy.net): the date cell is identified by id
    # and the title cell has no class, with relative dated hrefs. The title link
    # is found via article_like_path? and the date comes from the url.
    html = <<~HTML
      <html><body><div class="row"><h1>All Articles</h1>
      <table id="archive-table"><tbody>
        <tr><td id="date">November 2025</td><td><a href="2025/11/17/compiling-ruby-to-machine-language">Compiling Ruby To Machine Language</a></td></tr>
        <tr><td id="date"></td><td><a href="2025/11/10/yarvs-internal-stack-and-your-ruby-stack">YARV's Internal Stack and Your Ruby Stack</a></td></tr>
        <tr><td id="date"></td><td><a href="2025/11/3/compiling-a-call-to-a-block">Compiling a Call to a Block</a></td></tr>
      </tbody></table></div></body></html>
    HTML

    articles = extract(html, base: BASE + "/archive")

    assert_equal 3, articles.length
    first = articles.find { |a| a[:title] == "Compiling Ruby To Machine Language" }
    assert first[:url].end_with?("/2025/11/17/compiling-ruby-to-machine-language")
    assert_equal Date.new(2025, 11, 17), first[:date]
  end

  test "extracts table rows with dates from the date cell" do
    html = <<~HTML
      <html><body><table class="archive">
        <tr><td class="title"><a href="/posts/a">First</a></td><td class="date">2024-01-15</td></tr>
        <tr><td class="title"><a href="/posts/b">Second</a></td><td class="date">2024-02-20</td></tr>
        <tr><td class="title"><a href="/posts/c">Third</a></td><td class="date">2024-03-25</td></tr>
      </table></body></html>
    HTML

    articles = extract(html)

    assert_equal 3, articles.length
    first = articles.find { |a| a[:title] == "First" }
    assert_equal Date.new(2024, 1, 15), first[:date]
  end

  # ---------------------------------------------------------------------------
  # Group B: Phase 1 thresholds and has_article_link? branches
  # ---------------------------------------------------------------------------

  test "succeeds with exactly three valid containers" do
    html = "<html><body>" + repeat(<<~ITEM, 3) + "</body></html>"
      <article><h2><a href="/posts/slug-%d">Title %d</a></h2></article>
    ITEM

    assert_equal 3, extract(html).length
  end

  test "articles whose only link is excluded are not counted" do
    html = <<~HTML
      <html><body>
        <article><h2><a href="/about">About</a></h2></article>
        <article><h2><a href="/category/tech">Tech</a></h2></article>
        <article><h2><a href="/tag/ruby">Ruby</a></h2></article>
      </body></html>
    HTML

    assert_empty extract(html)
  end

  test "detects an article link when the container itself is an anchor" do
    html = "<html><body><div class=\"flex-col\">" +
      repeat(%(<a href="/posts/slug-%d" class="post-item">Title %d</a>), 3) +
      "</div></body></html>"

    assert_equal 3, extract(html).length
  end

  test "detects an article link nested inside the container" do
    html = "<html><body><ul class=\"posts\">" +
      repeat(%(<li><span>meta</span><a href="/blog/slug-%d">Title %d</a></li>), 3) +
      "</ul></body></html>"

    assert_equal 3, extract(html).length
  end

  # ---------------------------------------------------------------------------
  # Group C: Phase 2 pattern discovery fallback
  # ---------------------------------------------------------------------------

  test "discovers a container pattern when no fast selector matches" do
    # div.entry is not in FAST_SELECTORS, but good_container? accepts "entry"
    # and pattern discovery infers the selector from sampled links.
    html = "<html><body>" +
      repeat(%(<div class="entry"><a href="/posts/slug-%d">Title %d</a></div>), 4) +
      "</body></html>"

    articles = extract(html)

    assert_equal 4, articles.length
    assert_equal %w[Title\ 1 Title\ 2 Title\ 3 Title\ 4].sort, articles.map { |a| a[:title] }.sort
  end

  test "discovers containers nested under a list wrapper" do
    html = "<html><body><ul class=\"articles\">" +
      repeat(%(<li class="entry"><a href="/posts/slug-%d">Title %d</a></li>), 4) +
      "</ul></body></html>"

    assert_equal 4, extract(html).length
  end

  # ---------------------------------------------------------------------------
  # Group D: Phase 3 direct link extraction (last resort)
  # ---------------------------------------------------------------------------

  test "extracts archive article links and ignores feed and directory index" do
    html = <<~HTML
      <html><body>
        <a href="/archive/">Archive</a>
        <a href="/blog/feed.atom">Atom</a>
        <a href="/archive/addressing-editor-content.html">Addressing Editor Content</a>
        <a href="/archive/value-reference-semantics.html">Value Reference Semantics</a>
        <a href="/archive/http-caching.html">HTTP Caching</a>
        <a href="/archive/interning.html">Interning</a>
        <a href="/archive/common-lisp-monads.html">Common Lisp Monads</a>
        <a href="/archive/mold.html">Mold</a>
        <a href="/archive/pcall.html">Pcall</a>
      </body></html>
    HTML

    articles = extract(html, base: BASE + "/archive")

    assert_equal 7, articles.length
    assert articles.all? { |a| a[:url].include?("/archive/") }
  end

  test "extracts links directly from the body when no container groups them" do
    # Links whose parent is <body> have no good container, so phases 1 and 2
    # fail and phase 3 maps each link to an article.
    html = "<html><body>" +
      repeat(%(<a href="/posts/slug-%d">Title %d</a>), 4) +
      "</body></html>"

    articles = extract(html)

    assert_equal 4, articles.length
    assert_equal %w[Title\ 1 Title\ 2 Title\ 3 Title\ 4].sort, articles.map { |a| a[:title] }.sort
  end

  test "falls back to title and aria-label attributes when link text is empty" do
    html = <<~HTML
      <html><body>
        <a href="/posts/a">First</a>
        <a href="/posts/b" title="Second"></a>
        <a href="/posts/c" aria-label="Third"></a>
      </body></html>
    HTML

    titles = extract(html).map { |a| a[:title] }

    assert_includes titles, "First"
    assert_includes titles, "Second"
    assert_includes titles, "Third"
  end

  test "extracts the publication date from a dated url" do
    html = <<~HTML
      <html><body>
        <a href="/2024/01/15/first">First</a>
        <a href="/2024/02/20/second">Second</a>
        <a href="/2024/03/25/third">Third</a>
      </body></html>
    HTML

    first = extract(html).find { |a| a[:title] == "First" }

    assert_equal Date.new(2024, 1, 15), first[:date]
  end

  test "deduplicates articles pointing at the same url" do
    html = <<~HTML
      <html><body>
        <a href="/posts/a">First</a>
        <a href="/posts/a">First again</a>
        <a href="/posts/b">Second</a>
        <a href="/posts/c">Third</a>
      </body></html>
    HTML

    articles = extract(html)

    assert_equal 3, articles.length
    assert_equal 1, articles.count { |a| a[:url] == "https://example.com/posts/a" }
  end

  test "sorts articles oldest first with undated articles last" do
    html = <<~HTML
      <html><body>
        <a href="/2024/03/01/march">March</a>
        <a href="/2024/01/01/january">January</a>
        <a href="/posts/undated">Undated</a>
        <a href="/2024/02/01/february">February</a>
      </body></html>
    HTML

    titles = extract(html).map { |a| a[:title] }

    assert_equal %w[January February March], titles.first(3)
    assert_equal "Undated", titles.last
  end

  # ---------------------------------------------------------------------------
  # Group E: container scoping (ArchiveContainerExtractor)
  # ---------------------------------------------------------------------------

  test "scopes extraction to the main container and ignores outside links" do
    html = <<~HTML
      <html><body>
        <nav><a href="/about">About</a><a href="/posts/outside">Outside</a></nav>
        <main>
          <article><h2><a href="/posts/inside-1">Inside 1</a></h2></article>
          <article><h2><a href="/posts/inside-2">Inside 2</a></h2></article>
          <article><h2><a href="/posts/inside-3">Inside 3</a></h2></article>
        </main>
      </body></html>
    HTML

    titles = extract(html).map { |a| a[:title] }

    assert_equal 3, titles.length
    assert_not_includes titles, "Outside"
  end

  test "searches the whole document when no container is recognized" do
    html = "<html><body>" + repeat(%(<a href="/posts/slug-%d">Title %d</a>), 4) + "</body></html>"

    assert_equal 4, extract(html).length
  end

  # ---------------------------------------------------------------------------
  # Group F: failure and edge cases
  # ---------------------------------------------------------------------------

  test "returns an empty array for an empty document" do
    assert_empty extract("<html><body></body></html>")
  end

  test "returns an empty array when there are no links" do
    assert_empty extract("<html><body><p>nothing to see</p></body></html>")
  end

  test "returns an empty array for navigation-only pages" do
    html = <<~HTML
      <html><body>
        <a href="/about">About</a>
        <a href="/category/tech">Tech</a>
        <a href="/tag/ruby">Ruby</a>
      </body></html>
    HTML

    assert_empty extract(html)
  end

  test "returns an empty array when every link is external" do
    html = "<html><body>" + repeat(%(<a href="https://other.com/post-%d">Title %d</a>), 5) + "</body></html>"

    assert_empty extract(html)
  end

  test "returns stray article links below the three-article threshold" do
    # Pinned behavior: phase 3 has no minimum, so even two stray article links
    # are returned. This documents current behavior rather than endorsing it.
    html = <<~HTML
      <html><body>
        <a href="/posts/a">First</a>
        <a href="/posts/b">Second</a>
      </body></html>
    HTML

    assert_equal 2, extract(html).length
  end

  test "drops a self-link equal to a path-scoped base url" do
    html = "<html><body>" +
      %(<a href="/blog">Blog index</a>) +
      repeat(%(<a href="/blog/slug-%d">Title %d</a>), 4) +
      "</body></html>"

    articles = extract(html, base: "https://example.com/blog")

    assert_equal 4, articles.length
    assert_not_includes articles.map { |a| a[:url] }, "https://example.com/blog"
  end

  # ---------------------------------------------------------------------------
  # Group G: flat-list archives with no per-article container
  #
  # Regression for codingwithjesse.com/blog/all/, where every post is a bare
  # <a> separated by <br><em>date</em> inside a single <section>, with no
  # <li>/<article>/<div> wrapper. Pattern discovery (phase 2) collapses onto the
  # generic "section" selector and, because the page also carries small
  # link-bearing sections (an "other pages" list with RSS/feed, a contact box),
  # matches three <section> elements and extracts only the first link from each
  # -- returning three "articles" (newest post, RSS, contact) instead of the
  # full list. Correct behavior falls through to phase 3 (direct link
  # extraction) and returns every post.
  # ---------------------------------------------------------------------------

  # slug => title, mirroring the real archive's flat list of posts
  FLAT_LIST_POSTS = {
    "rockstar-developers"   => "Cleaning up after AI rockstar developers",
    "a-rabbit-hole"         => "A rabbit hole in 5 commits",
    "svelte-features"       => "7 Svelte features that bring me joy",
    "a-url-is-forever"      => "A URL is forever",
    "advent-of-code-2022"   => "Advent of Code 2022",
    "back-from-jax"         => "Back from JAX"
  }.freeze

  # Reproduces the codingwithjesse.com/blog/all/ markup: a flat list of bare
  # anchors separated by <br><em>date</em> inside one <section>, plus the two
  # extra link-bearing sections that trigger the one-article-per-section collapse.
  def flat_list_archive
    posts = FLAT_LIST_POSTS.map do |slug, title|
      %(<br><em>2024/01/01</em>\n<a href="/blog/#{slug}/">#{title}</a>)
    end.join("\n")

    <<~HTML
      <html><body>
        <section><p>Here are the articles I have written.
          #{posts}
          <a href="/newsletter">Subscribe to the newsletter</a>
        </p></section>
        <section><p>Here are some other pages on this site.
          <a href="/blog/rss">RSS</a>
          <a href="/blog/feed">feed</a>
          <a href="/blog/search">Search</a>
        </p></section>
        <section id="contact"><h2>Contact Jesse</h2>
          <p>Email me at <a href="/contact-me">get in touch</a></p>
        </section>
      </body></html>
    HTML
  end

  test "extracts every post from a flat-list archive with no per-article container" do
    titles = extract(flat_list_archive, base: BASE + "/blog/all").map { |a| a[:title] }

    FLAT_LIST_POSTS.each_value do |title|
      assert_includes titles, title, "expected flat-list post #{title.inspect} to be extracted"
    end
  end

  test "flat-list archive does not collapse to one article per section" do
    # Pins the bug: today pattern discovery returns exactly three articles -- the
    # newest post, the RSS link, and the contact box -- one per <section>.
    articles = extract(flat_list_archive, base: BASE + "/blog/all")

    assert_operator articles.length, :>=, FLAT_LIST_POSTS.length
  end

  # ---------------------------------------------------------------------------
  # Group H: Debug "what-if" trace (P4)
  # ---------------------------------------------------------------------------

  test "debug mode is off by default, leaving the what-if fields nil" do
    html = "<html><body>" + repeat(<<~ITEM, 3) + "</body></html>"
      <article><h2><a href="/posts/slug-%d">Title %d</a></h2></article>
    ITEM

    trace = trace_for(html)

    assert_nil trace.phase_results
    assert_nil trace.container_candidates
  end

  test "debug mode reports all three phases with exactly one chosen" do
    html = "<html><body>" + repeat(<<~ITEM, 3) + "</body></html>"
      <article><h2><a href="/posts/slug-%d">Title %d</a></h2></article>
    ITEM

    trace = trace_for(html, debug: true)

    assert_equal 3, trace.phase_results.length
    chosen = trace.phase_results.select { |p| p[:chosen] }
    assert_equal 1, chosen.length
    # Phase 1 (fast selectors) wins for semantic article containers, and the
    # chosen flag matches the phase the cascade actually selected.
    assert_equal :try_fast_selectors_with_info, chosen.first[:phase]
    assert_equal trace.phase, chosen.first[:phase]
  end

  test "debug mode reports differing per-phase article counts" do
    # Phase 1 sees 3 semantic article containers and wins; phase 3 (direct links)
    # would additionally pick up the two stray article links, so its count differs.
    strays = %(<a href="/posts/stray-a">Stray A</a><a href="/posts/stray-b">Stray B</a>)
    html = "<html><body>" + repeat(<<~ITEM, 3) + strays + "</body></html>"
      <article><h2><a href="/posts/slug-%d">Title %d</a></h2></article>
    ITEM

    trace = trace_for(html, debug: true)
    by_phase = trace.phase_results.index_by { |p| p[:phase] }

    assert by_phase[:try_fast_selectors_with_info][:chosen]
    assert_equal 3, by_phase[:try_fast_selectors_with_info][:articles]
    assert_equal 5, by_phase[:extract_from_links_directly][:articles]
    assert_not by_phase[:extract_from_links_directly][:chosen]
  end

  test "debug mode lists container candidates with the chosen default marked" do
    html = "<html><body><main>" + repeat(<<~ITEM, 3) + "</main></body></html>"
      <article><h2><a href="/posts/slug-%d">Title %d</a></h2></article>
    ITEM

    candidates = WebProcessor::ArchiveContainerExtractor.container_candidates(BASE, doc(html))

    chosen = candidates.select { |c| c[:chosen] }
    assert_equal 1, chosen.length
    assert_equal "main", chosen.first[:selector]
    assert_equal :default, chosen.first[:source]
    assert chosen.first[:link_count] >= 2
  end

  # ---------------------------------------------------------------------------
  # Flat list structure
  # ---------------------------------------------------------------------------

  def flat_list_html
    list = repeat(<<~ITEM, 12)
      <a href="/blog/post-%d/">Post %d</a><br><em>2023/01/%d</em>
    ITEM
    <<~HTML
      <html><body>
        <main><section>#{list}</section></main>
        <section><a href="/blog/rss">RSS</a></section>
        <footer><section><a href="/contact-jesse">Contact Jesse</a></section></footer>
      </body></html>
    HTML
  end

  test "flat anchor list with no per-item wrapper extracts all links, not one per section" do
    html = flat_list_html
    articles = extract(html)

    assert_equal 12, articles.length
    assert articles.all? { |a| a[:url].include?("/blog/post-") }
  end

  test "flat anchor list falls through to direct link extraction phase" do
    html = flat_list_html
    trace = trace_for(html, debug: true)
    assert_equal :extract_from_links_directly, trace.phase
  end

  test "find_article_links returns the array of link elements, not the trace hash" do
    html = "<html><body><main>" + repeat(<<~ITEM, 4) + "</main></body></html>"
      <a href="/blog/post-%d/">Post %d</a>
    ITEM

    links = WebProcessor::ArticleExtractor.find_article_links(doc(html), BASE)

    assert_equal 4, links.length
    assert links.all? { |l| l.name == "a" }
  end

  test "genuine per-item containers are not rejected by the collapse guard" do
    html = "<html><body><main>" + repeat(<<~ITEM, 5) + "</main></body></html>"
      <section class="entry">
        <h2><a href="/blog/post-%d/">Post %d</a></h2>
        <em>2023/01/%d</em>
      </section>
    ITEM

    trace = trace_for(html, debug: true)
    articles = extract(html)

    # Phase 2 produced a valid per-item pattern (~1 link per container),
    # so the collapse guard must NOT fire and force a Phase 3 fallback.
    assert_equal :discover_pattern_from_links_with_info, trace.phase
    assert_equal 5, articles.length
    assert articles.all? { |a| a[:url].include?("/blog/post-") }
  end
end
