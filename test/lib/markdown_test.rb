require "test_helper"

class MarkdownTest < ActionView::TestCase
  ENGINES = { redcarpet: Markdown::REDCARPET, commonmarker: Markdown::COMMONMARKER }

  # Same expected output for every engine.
  def assert_renders(markdown, expected, engines: ENGINES.keys)
    engines.each do |name|
      use_engine(ENGINES.fetch(name)) do
        assert_equal expected, Markdown.to_html(markdown),
          "engine=#{name} produced unexpected output"
      end
    end
  end

  # Different expected output per engine. Pass any subset of engine kwargs;
  # missing engines are skipped (used for engine-only features).
  def assert_renders_per_engine(markdown, **expected_per_engine)
    expected_per_engine.each do |name, expected|
      use_engine(ENGINES.fetch(name)) do
        assert_equal expected, Markdown.to_html(markdown),
          "engine=#{name} produced unexpected output"
      end
    end
  end

  # Same input, both engines, custom block of assertions per engine.
  def with_each_engine(engines: ENGINES.keys)
    engines.each do |name|
      use_engine(ENGINES.fetch(name)) { yield name }
    end
  end

  # --- Blank input ---

  test "returns empty string for nil" do
    assert_renders nil, ""
  end

  test "returns empty string for empty string" do
    assert_renders "", ""
  end

  test "returns empty string for whitespace" do
    assert_renders "   ", ""
  end

  test "preserves leading and trailing whitespace by returning empty for tabs and newlines" do
    assert_renders "\t\n  \n", ""
  end

  test "returns html_safe output" do
    with_each_engine { assert Markdown.to_html("hello").html_safe? }
  end

  test "html_safe output for blank input" do
    with_each_engine do
      assert Markdown.to_html(nil).html_safe?
      assert Markdown.to_html("").html_safe?
      assert Markdown.to_html("   ").html_safe?
    end
  end

  # --- Paragraphs and line breaks ---

  test "renders a paragraph" do
    assert_renders "Hello world", "<p>Hello world</p>\n"
  end

  test "renders multiple paragraphs separated by blank lines" do
    # CommonMark does not insert a blank line between adjacent block elements
    assert_renders_per_engine "First paragraph.\n\nSecond paragraph.",
      redcarpet:    "<p>First paragraph.</p>\n\n<p>Second paragraph.</p>\n",
      commonmarker: "<p>First paragraph.</p>\n<p>Second paragraph.</p>\n"
  end

  test "renders line break with trailing spaces" do
    assert_renders "line one  \nline two", "<p>line one<br>\nline two</p>\n"
  end

  # --- Headings ---

  test "renders h1" do
    assert_renders "# Title", "<h1>Title</h1>\n"
  end

  test "renders h2" do
    assert_renders "## Subtitle", "<h2>Subtitle</h2>\n"
  end

  test "renders h3" do
    assert_renders "### Section", "<h3>Section</h3>\n"
  end

  test "renders h4" do
    assert_renders "#### Heading", "<h4>Heading</h4>\n"
  end

  test "renders h5" do
    assert_renders "##### Heading", "<h5>Heading</h5>\n"
  end

  test "renders h6" do
    assert_renders "###### Heading", "<h6>Heading</h6>\n"
  end

  test "renders setext h1 with equals" do
    assert_renders "Title\n=====", "<h1>Title</h1>\n"
  end

  test "renders setext h2 with dashes" do
    assert_renders "Title\n-----", "<h2>Title</h2>\n"
  end

  test "renders strong inside heading" do
    assert_renders "## A **bold** title", "<h2>A <strong>bold</strong> title</h2>\n"
  end

  # --- Inline emphasis ---

  test "renders bold text" do
    assert_renders "**bold**", "<p><strong>bold</strong></p>\n"
  end

  test "renders bold using double underscores" do
    assert_renders "__bold__", "<p><strong>bold</strong></p>\n"
  end

  test "renders italic text" do
    assert_renders "*italic*", "<p><em>italic</em></p>\n"
  end

  test "renders bold and italic combined" do
    # CommonMark spec wraps em outside strong for ***both***; Redcarpet does strong outside em
    assert_renders_per_engine "***both***",
      redcarpet:    "<p><strong><em>both</em></strong></p>\n",
      commonmarker: "<p><em><strong>both</strong></em></p>\n"
  end

  # CommonMark-only: Redcarpet parses ***TL;DR:** ...* as strong inside em differently
  test "renders the TL;DR snippet correctly" do
    text = "***TL;DR:** Keep an internally public, daily journal of snippets describing the impact of your work, written with the intention of adding them to your performance review.*"
    expected = "<p><em><strong>TL;DR:</strong> Keep an internally public, daily journal of snippets describing the impact of your work, written with the intention of adding them to your performance review.</em></p>\n"
    assert_renders_per_engine text, commonmarker: expected
  end

  test "renders strikethrough" do
    assert_renders "~~gone~~", "<p><del>gone</del></p>\n"
  end

  test "renders strikethrough within a sentence" do
    assert_renders "This is ~~old~~ news", "<p>This is <del>old</del> news</p>\n"
  end

  test "renders highlight" do
    assert_renders "==highlight==", "<p><mark>highlight</mark></p>\n"
  end

  test "renders highlight within a sentence" do
    assert_renders "Note the ==important== bit", "<p>Note the <mark>important</mark> bit</p>\n"
  end

  test "renders underline using underscore" do
    assert_renders "_underlined_", "<p><u>underlined</u></p>\n"
  end

  test "renders mixed bold and italic in same paragraph" do
    assert_renders "Some **bold** and *italic* words",
      "<p>Some <strong>bold</strong> and <em>italic</em> words</p>\n"
  end

  # --- Inline code ---

  test "renders inline code" do
    assert_renders "Use `code` here", "<p>Use <code>code</code> here</p>\n"
  end

  test "renders inline code with special characters" do
    assert_renders "`a < b && c > d`", "<p><code>a &lt; b &amp;&amp; c &gt; d</code></p>\n"
  end

  test "renders inline code containing backticks using double backticks" do
    assert_renders "``a `b` c``", "<p><code>a `b` c</code></p>\n"
  end

  # --- Quotes ---

  test "renders blockquote" do
    assert_renders "> quoted", "<blockquote>\n<p>quoted</p>\n</blockquote>\n"
  end

  test "renders blockquote with multiple paragraphs" do
    # CommonMark does not insert a blank line between adjacent block elements
    assert_renders_per_engine "> first\n>\n> second",
      redcarpet:    "<blockquote>\n<p>first</p>\n\n<p>second</p>\n</blockquote>\n",
      commonmarker: "<blockquote>\n<p>first</p>\n<p>second</p>\n</blockquote>\n"
  end

  test "renders nested blockquotes" do
    # CommonMark does not insert a blank line between adjacent block elements
    assert_renders_per_engine "> outer\n>\n> > inner",
      redcarpet:    "<blockquote>\n<p>outer</p>\n\n<blockquote>\n<p>inner</p>\n</blockquote>\n</blockquote>\n",
      commonmarker: "<blockquote>\n<p>outer</p>\n<blockquote>\n<p>inner</p>\n</blockquote>\n</blockquote>\n"
  end

  test "renders inline quote syntax" do
    assert_renders 'A "quoted" word', "<p>A <q>quoted</q> word</p>\n"
  end

  # --- Lists ---

  test "renders unordered lists" do
    assert_renders "- one\n- two\n- three",
      "<ul>\n<li>one</li>\n<li>two</li>\n<li>three</li>\n</ul>\n"
  end

  test "renders ordered lists" do
    assert_renders "1. first\n2. second",
      "<ol>\n<li>first</li>\n<li>second</li>\n</ol>\n"
  end

  test "renders nested unordered lists" do
    # CommonMark uses a single newline before nested lists and adds \n before </li>
    assert_renders_per_engine "- one\n  - one.a\n  - one.b\n- two",
      redcarpet:    "<ul>\n<li>one\n\n<ul>\n<li>one.a</li>\n<li>one.b</li>\n</ul></li>\n<li>two</li>\n</ul>\n",
      commonmarker: "<ul>\n<li>one\n<ul>\n<li>one.a</li>\n<li>one.b</li>\n</ul>\n</li>\n<li>two</li>\n</ul>\n"
  end

  test "renders mixed nested ordered list inside unordered list" do
    # CommonMark uses a single newline before the nested list and adds \n before </li>
    assert_renders_per_engine "- outer\n  1. inner one\n  2. inner two",
      redcarpet:    "<ul>\n<li>outer\n\n<ol>\n<li>inner one</li>\n<li>inner two</li>\n</ol></li>\n</ul>\n",
      commonmarker: "<ul>\n<li>outer\n<ol>\n<li>inner one</li>\n<li>inner two</li>\n</ol>\n</li>\n</ul>\n"
  end

  test "renders ordered list starting at custom number" do
    # Redcarpet ignores the custom start number and always starts at 1;
    # CommonMark preserves it via the start attribute
    assert_renders_per_engine "3. third\n4. fourth",
      redcarpet:    "<ol>\n<li>third</li>\n<li>fourth</li>\n</ol>\n",
      commonmarker: "<ol start=\"3\">\n<li>third</li>\n<li>fourth</li>\n</ol>\n"
  end

  test "renders link inside list item" do
    # CommonMark adds a newline before </li>
    assert_renders_per_engine "- see [docs](https://example.com)",
      redcarpet:    %(<ul>\n<li>see <a href="https://example.com">docs</a></li>\n</ul>\n),
      commonmarker: %(<ul>\n<li>see <a href="https://example.com">docs</a>\n</li>\n</ul>\n)
  end

  test "renders inline code inside list item" do
    # CommonMark adds a newline before </li>
    assert_renders_per_engine "- run `bin/dev`",
      redcarpet:    "<ul>\n<li>run <code>bin/dev</code></li>\n</ul>\n",
      commonmarker: "<ul>\n<li>run <code>bin/dev</code>\n</li>\n</ul>\n"
  end

  # CommonMark-only: Redcarpet does not support loose list items (multi-paragraph list items)
  test "renders multi-paragraph list items" do
    md = "- first paragraph\n\n  second paragraph of first item\n- second item"
    use_engine Markdown::COMMONMARKER do
      result = Markdown.to_html(md)
      assert_includes result, "<ul>"
      assert_includes result, "<p>first paragraph</p>"
      assert_includes result, "<p>second paragraph of first item</p>"
    end
  end

  # --- Links and images ---

  test "renders links" do
    assert_renders "[Rails](https://rubyonrails.org)",
      %(<p><a href="https://rubyonrails.org">Rails</a></p>\n)
  end

  test "renders multiple links in same paragraph" do
    assert_renders "See [one](https://a.com) and [two](https://b.com)",
      %(<p>See <a href="https://a.com">one</a> and <a href="https://b.com">two</a></p>\n)
  end

  test "autolinks bare URLs" do
    assert_renders "Visit https://example.com today",
      %(<p>Visit <a href="https://example.com">https://example.com</a> today</p>\n)
  end

  test "autolinks email-like URLs only when prefixed" do
    assert_renders "Site: http://example.com",
      %(<p>Site: <a href="http://example.com">http://example.com</a></p>\n)
  end

  # No CommonMark counterpart: the quote preprocessor converts "Title" inside link/image
  # title syntax before CommonMark parses it, breaking the link structure.
  test "renders link with title attribute" do
    assert_renders_per_engine '[site](https://example.com "Example")',
      redcarpet: %(<p><a href="https://example.com" title="Example">site</a></p>\n)
  end

  test "renders images" do
    assert_renders "![alt text](https://example.com/img.png)",
      %(<p><img src="https://example.com/img.png" alt="alt text"></p>\n)
  end

  # No CommonMark counterpart: the quote preprocessor converts "Caption" inside image
  # title syntax before CommonMark parses it, breaking the image structure.
  test "renders image with title attribute" do
    assert_renders_per_engine '![alt](https://example.com/img.png "Caption")',
      redcarpet: %(<p><img src="https://example.com/img.png" alt="alt" title="Caption"></p>\n)
  end

  # --- Horizontal rules ---

  test "renders horizontal rule" do
    assert_renders "---", "<hr>\n"
  end

  test "renders horizontal rule with asterisks" do
    assert_renders "***", "<hr>\n"
  end

  test "renders horizontal rule with underscores" do
    assert_renders "___", "<hr>\n"
  end

  test "renders consecutive horizontal rules" do
    # CommonMark does not insert a blank line between adjacent block elements
    assert_renders_per_engine "---\n\n---",
      redcarpet:    "<hr>\n\n<hr>\n",
      commonmarker: "<hr>\n<hr>\n"
  end

  # --- Tables ---

  test "renders tables" do
    table = <<~MD
      | Name | Role |
      | ---- | ---- |
      | Ada  | Dev  |
      | Bob  | PM   |
    MD

    redcarpet_expected = <<~HTML
      <table><thead>
      <tr>
      <th>Name</th>
      <th>Role</th>
      </tr>
      </thead><tbody>
      <tr>
      <td>Ada</td>
      <td>Dev</td>
      </tr>
      <tr>
      <td>Bob</td>
      <td>PM</td>
      </tr>
      </tbody></table>
    HTML

    # CommonMark adds newlines after <table>, <thead>, <tbody> opening/closing tags
    commonmarker_expected = "<table>\n<thead>\n<tr>\n<th>Name</th>\n<th>Role</th>\n</tr>\n</thead>\n" \
                            "<tbody>\n<tr>\n<td>Ada</td>\n<td>Dev</td>\n</tr>\n" \
                            "<tr>\n<td>Bob</td>\n<td>PM</td>\n</tr>\n</tbody>\n</table>\n"

    assert_renders_per_engine table,
      redcarpet:    redcarpet_expected,
      commonmarker: commonmarker_expected
  end

  test "renders table with column alignment" do
    table = <<~MD
      | Left | Center | Right |
      | :--- | :----: | ----: |
      | a    | b      | c     |
    MD

    use_engine Markdown::REDCARPET do
      result = Markdown.to_html(table)
      assert_includes result, %(<th style="text-align: left">Left</th>)
      assert_includes result, %(<th style="text-align: center">Center</th>)
      assert_includes result, %(<th style="text-align: right">Right</th>)
    end

    # CommonMark uses align attribute instead of style attribute for column alignment
    use_engine Markdown::COMMONMARKER do
      result = Markdown.to_html(table)
      assert_includes result, %(<th align="left">Left</th>)
      assert_includes result, %(<th align="center">Center</th>)
      assert_includes result, %(<th align="right">Right</th>)
    end
  end

  # --- Code blocks ---

  test "renders fenced code blocks with syntax highlighting" do
    code = "```ruby\ndef hello\nend\n```"
    body = %(<pre class="highlight not-prose"><code class="language-ruby"><span class="k">def</span> <span class="nf">hello</span>\n<span class="k">end</span>\n</code></pre>)
    # CommonMark appends a trailing newline after </pre>
    assert_renders_per_engine code,
      redcarpet:    body,
      commonmarker: body + "\n"
  end

  test "renders fenced code with unknown language using plain text" do
    code = "```nonexistentlang\nsome content\n```"
    body = %(<pre class="highlight not-prose"><code class="language-nonexistentlang">some content\n</code></pre>)
    # CommonMark appends a trailing newline after </pre>
    assert_renders_per_engine code,
      redcarpet:    body,
      commonmarker: body + "\n"
  end

  test "renders fenced code block without language" do
    assert_renders "```\nplain content\n```", "<pre><code>plain content\n</code></pre>\n"
  end

  test "renders fenced code block preserving indentation" do
    code = "```ruby\n  indented\n```"
    with_each_engine do
      result = Markdown.to_html(code)
      assert_includes result, "indented"
      assert_includes result, %(class="language-ruby")
    end
  end

  test "renders indented code block" do
    assert_renders "    line one\n    line two",
      "<pre><code>line one\nline two\n</code></pre>\n"
  end

  # --- Escaping ---

  test "escapes ampersands in text" do
    assert_renders "AT&T and Co.", "<p>AT&amp;T and Co.</p>\n"
  end

  test "escapes less than and greater than in plain text" do
    assert_renders "1 < 2 and 3 > 2", "<p>1 &lt; 2 and 3 &gt; 2</p>\n"
  end

  test "escapes less than and greater than in code blocks" do
    code = "```ruby\n1 < 2\n```"
    expected = "<pre class=\"highlight not-prose\"><code class=\"language-ruby\"><span class=\"mi\">1</span> <span class=\"o\">&lt;</span> <span class=\"mi\">2</span>\n</code></pre>"
    assert_renders_per_engine code,
      redcarpet:    expected,
      commonmarker: expected + "\n"
  end

  test "escapes less than and greater than in code blocks html" do
    code = "```html\n<div>hello</div>\n```"
    expected = "<pre class=\"highlight not-prose\"><code class=\"language-html\"><span class=\"nt\">&lt;div&gt;</span>hello<span class=\"nt\">&lt;/div&gt;</span>\n</code></pre>"
    assert_renders_per_engine code,
      redcarpet:    expected,
      commonmarker: expected + "\n"
  end

  test "escapes html special characters in code blocks" do
    code = "```html\n<a href=\"foo?a=1&b=2\">bar</a>\n```"
    expected = "<pre class=\"highlight not-prose\"><code class=\"language-html\"><span class=\"nt\">&lt;a</span> <span class=\"na\">href=</span><span class=\"s\">\"foo?a=1&amp;b=2\"</span><span class=\"nt\">&gt;</span>bar<span class=\"nt\">&lt;/a&gt;</span>\n</code></pre>"
    assert_renders_per_engine code,
      redcarpet:    expected,
      commonmarker: expected + "\n"
  end
end
