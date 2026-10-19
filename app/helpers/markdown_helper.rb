# Renders article content (markdown or extracted HTML) safely.
#
# Article bodies originate from external blogs we crawl, so the HTML is fully
# attacker-controlled. CommonMarker is configured with `unsafe: true` to keep
# legitimate inline HTML (tables, figures, callouts, etc.) intact, so we MUST
# strip executable content here before the view emits it.
#
# The allow-list keeps every visual tag a long-form blog post normally uses but
# rejects anything that can execute JavaScript or load active content:
# no <script>, <iframe>, <object>, <embed>, <form>, <link>, <style>, <meta>,
# <base>. Dangerous URL schemes (javascript:, vbscript:, ...) and all on*
# event handlers are stripped automatically by Rails::Html::SafeListSanitizer.
module MarkdownHelper
  ARTICLE_ALLOWED_TAGS = %w[
    p br hr
    h1 h2 h3 h4 h5 h6
    strong em b i u s del ins mark small sub sup
    blockquote q cite
    pre code kbd samp var
    ul ol li dl dt dd
    a img figure figcaption picture source
    table thead tbody tfoot tr th td caption colgroup col
    div span
    abbr address
  ].freeze

  # `class` is required for Rouge syntax-highlight spans and prose styling.
  # `align` preserves CommonMark table column alignment.
  # `style` is intentionally OMITTED: inline CSS enables clickjacking overlays
  # (position:fixed), history sniffing, and exfiltration via background-image.
  ARTICLE_ALLOWED_ATTRS = %w[
    href src alt title srcset sizes loading
    width height
    colspan rowspan align scope
    start type reversed value
    id class lang dir
  ].freeze

  def render_markdown(text)
    sanitize_article_html(Markdown.to_html(text))
  end

  def sanitize_article_html(html)
    sanitize(html, tags: ARTICLE_ALLOWED_TAGS, attributes: ARTICLE_ALLOWED_ATTRS)
  end
end
