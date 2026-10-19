# Define the constant before requiring redcarpet so its compat file
# (which does `Markdown = RedcarpetCompat unless defined?(Markdown)`) skips it.
module Markdown; end
require "cgi"
require "redcarpet"
require "commonmarker"
require "rouge"

module Markdown
  REDCARPET    = 0
  COMMONMARKER = 1

  mattr_accessor :engine
  self.engine = COMMONMARKER

  def self.to_html(text)
    return "".html_safe if text.blank?
    html = case engine
    when REDCARPET    then Redcarpet.render(text)
    when COMMONMARKER then Commonmarker.render(text)
    end
    html.html_safe
  end

  def self.to_text(text)
    return "" if text.blank?
    html = case engine
    when REDCARPET    then Redcarpet.render(text)
    when COMMONMARKER then Commonmarker.render(text)
    end
    ActionController::Base.helpers.strip_tags(html)
  end

  module Redcarpet
    class CodeRenderer < ::Redcarpet::Render::HTML
      def block_code(code, language)
        return %(<pre><code>#{CGI.escapeHTML(code)}</code></pre>\n) if language.nil?

        lexer = Rouge::Lexer.find(language) || Rouge::Lexers::PlainText
        formatter = Rouge::Formatters::HTML.new
        formatted = formatter.format(lexer.lex(code))
        %(<pre class="highlight not-prose"><code class="language-#{language}">#{formatted}</code></pre>)
      end
    end

    def self.render(text)
      ::Redcarpet::Markdown.new(
        CodeRenderer,
        autolink: true,
        tables: true,
        fenced_code_blocks: true,
        strikethrough: true,
        underline: true,
        highlight: true,
        quote: true,
      ).render(text)
    end
  end

  module Commonmarker
    def self.render(text)
      preprocessed = Markdown.preprocess(text)
      html = ::Commonmarker.to_html(preprocessed,
        options: {
          parse:     { smart: false },                                  # OFF — we handle quotes ourselves
          render:    { unsafe: true, github_pre_lang: false },          # github_pre_lang: false puts lang on code[class], not pre[lang]
          extension: { table: true, strikethrough: true, autolink: true, header_ids: nil }
        },
        plugins: { syntax_highlighter: nil }                            # disable built-in highlighter; Rouge handles it via post-processing
      )
      Markdown.highlight_code_blocks(html)
    end
  end

  # Apply inline syntax transforms (_underline_, ==mark==, "quote") only to
  # non-code regions so fenced code blocks and inline code spans pass through
  # untouched. Without this guard, content like "foo" inside a ```html block
  # would be rewritten to <q>foo</q> before CommonMarker parsed it.
  def self.preprocess(text)
    text.split(/(^```.*?^```$|``[^`\n]+``|`[^`\n]+`)/m).each_with_index.map { |part, i|
      if i.odd?
        part
      else
        part
          .gsub(/(?<![A-Za-z0-9_])_([^_\n]+?)_(?![A-Za-z0-9_])/, '<u>\1</u>')
          .gsub(/==([^=\n]+?)==/, '<mark>\1</mark>')
          .gsub(/"([^"\n]+?)"/, '<q>\1</q>')
      end
    }.join
  end

  def self.highlight_code_blocks(html)
    fragment = Nokogiri::HTML.fragment(html)
    fragment.css('pre > code[class^="language-"]').each do |node|
      code = node.text
      language = node["class"].sub(/^language-/, "") # strip language- prefix
      lexer = Rouge::Lexer.find(language) || Rouge::Lexers::PlainText
      formatter = Rouge::Formatters::HTML.new
      formatted = formatter.format(lexer.lex(code))
      node.parent.replace(%(<pre class="highlight not-prose"><code class="language-#{language}">#{formatted}</code></pre>))
    end
    fragment.to_html
  end
end
