require "test_helper"
require "open3"
require "json"

# Integration test that runs the real defuddle library (via a Node subprocess)
# to verify it preserves language identifiers on code blocks. Specifically
# guards against regressions where a language is missing from defuddle's
# CODE_LANGUAGES set (see tools/defuddle/src/elements/code.ts).
class DefuddleTest < ActiveSupport::TestCase
  EXTRACT_SCRIPT = Rails.root.join("test", "tools", "defuddle_extract.mjs")

  setup do
    skip "node executable not found on PATH" unless system("command -v node > /dev/null 2>&1")
  end

  test "preserves language-erb on Jekyll/Rouge code block" do
    result = defuddle_extract(jekyll_code_block(language: "erb", code: erb_snippet))

    assert_includes result["contentHtml"], 'class="language-erb"',
      "expected contentHtml to retain language-erb class, got:\n#{result["contentHtml"]}"
    assert_includes result["contentMd"], "```erb\n",
      "expected contentMd to use ```erb fence, got:\n#{result["contentMd"]}"
  end

  test "preserves language-ruby on Jekyll/Rouge code block (control case)" do
    result = defuddle_extract(jekyll_code_block(language: "ruby", code: ruby_snippet))

    assert_includes result["contentHtml"], 'class="language-ruby"'
    assert_includes result["contentMd"], "```ruby\n"
  end

  test "preserves language for both erb and ruby in the same article" do
    html = article_with_blocks(
      { language: "erb",  code: erb_snippet },
      { language: "ruby", code: ruby_snippet }
    )
    result = defuddle_extract(html)

    assert_includes result["contentHtml"], 'class="language-erb"'
    assert_includes result["contentHtml"], 'class="language-ruby"'
    assert_includes result["contentMd"], "```erb\n"
    assert_includes result["contentMd"], "```ruby\n"
  end

  private
    # Spawns the Node helper, pipes HTML through stdin, and returns the parsed
    # JSON response. Fails the test if the subprocess exits non-zero so any
    # JS-side error is visible in the test output.
    def defuddle_extract(html)
      stdout, stderr, status = Open3.capture3("node", EXTRACT_SCRIPT.to_s, stdin_data: html)
      unless status.success?
        flunk "defuddle extraction failed (exit=#{status.exitstatus}):\nSTDERR:\n#{stderr}\nSTDOUT:\n#{stdout}"
      end
      JSON.parse(stdout)
    end

    # Wraps a code snippet in the markup Jekyll's Rouge highlighter emits.
    def jekyll_code_block(language:, code:)
      article_with_blocks({ language: language, code: code })
    end

    # Builds a full HTML document around one or more Jekyll-style code blocks.
    # Surrounding prose is needed so defuddle picks the <article> as the main
    # content rather than treating the page as an index/listing.
    def article_with_blocks(*blocks)
      block_html = blocks.map do |b|
        <<~BLOCK
          <div class="language-#{b[:language]} highlighter-rouge"><div class="highlight"><pre class="highlight"><code>#{b[:code]}
          </code></pre></div></div>
          <p>Filler paragraph between or after code so defuddle has enough surrounding prose to recognize this as article content rather than a stub page.</p>
        BLOCK
      end.join("\n")

      <<~HTML
        <!DOCTYPE html>
        <html><head><title>Test Article About Programming Templates</title></head>
        <body>
          <article>
            <h1>Test Article About Programming Templates</h1>
            <p>An introductory paragraph long enough to count as actual content so defuddle does not treat this as a listing or index page during extraction.</p>
            #{block_html}
            <p>A closing paragraph that wraps up the article body with enough words to keep defuddle's scoring happy.</p>
          </article>
        </body></html>
      HTML
    end

    def erb_snippet
      %(<span class="nt">&lt;p&gt;</span>Hello World! <span class="c">&lt;%# missing &lt;/p&gt; %&gt;</span>)
    end

    def ruby_snippet
      %(<span class="k">def</span> <span class="nf">hello</span>\n  <span class="nb">puts</span> <span class="s">'world'</span>\n<span class="k">end</span>)
    end
end
