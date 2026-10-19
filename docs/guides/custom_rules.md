# Custom Rules Guide

This guide explains how to create and manage custom extraction rules for web scraping in Retrofeed.

```ruby
class WebProcessor::Domains::PaulGraham < WebProcessor::Domains::Base
  host "paulgraham.com"   # also matches www.paulgraham.com

  # --- Declarative rules (simple cases) ---
  container css: "body > table > tbody > tr > td:nth-child(3) > table:nth-child(6)",
            fallback_css: "html body table tbody tr td table"

  allowed_external_domains %w[turbifycdn.com]

  author static: "Paul Graham"

  # --- Imperative hook (complex cases) ---
  # Any of { extract_date, extract_author, extract_title, extract_container }
  # can be overridden with a method taking (doc, url) and returning the value
  # (or nil to fall back to the generic extractor).
  def extract_date(doc, url)
    # custom logic here; return Date or nil
  end
end
```

## Creating a Custom Rule

To create a custom rule for a specific website:

1. Create a new file in `app/services/web_processor/domains/` with the domain name (e.g., `example_com.rb`)
2. Define a class that inherits from `WebProcessor::Domains::Base`
3. Use the DSL methods to declare your extraction rules
4. Override imperative hooks if needed for complex logic

## DSL Methods

- `host(host)` - Specifies the domain(s) this rule applies to
- `container(css: "...", fallback_css: "...")` - CSS selectors for the main content container
- `author(css: "...", fallback_css: "...", static: "Author Name")` - Author extraction rules
- `title(css: "...", fallback_css: "...")` - Title extraction rules
- `date(css: "...", fallback_css: "...")` - Date extraction rules
- `allowed_external_domains(domains)` - Array of domains allowed for external content

## Imperative Hooks

For complex extraction logic, override these methods:

- `extract_date(doc, url)` - Custom date extraction
- `extract_author(doc, url)` - Custom author extraction  
- `extract_title(doc, url)` - Custom title extraction
- `extract_container(doc, url)` - Custom container extraction

Each method receives the Nokogiri document and URL, and should return the extracted value or nil to fall back to generic extraction. This methods can also be overwritten.

## Example different date extraction patterns

```ruby
class WebProcessor::CustomRules::AntirezDotCom < WebProcessor::CustomRules::Base
  host "antirez.com"
  author static: "Salvatore Sanfilippo"
  
  date css: "time.published",
       transform: ->(text) {
         # Preprocess the text here
         cleaned = text.gsub(/Published on\s*/i, '').strip
         # Try to parse as ISO8601 date
         Date.iso8601(cleaned) rescue nil
       }
end
```

```ruby
date css: "time.published",
     regex: /(\d{4}-\d{2}-\d{2})/,  # Extract date pattern
     capture: 1,                    # Use first capture group
     transform: :iso8601           # Convert to date
```

```ruby
date css: "time.published",
     regex: /Published: (.+?)\s*\|/,  # Extract text after "Published: "
     capture: 1,
     transform: ->(text) {
       # Additional cleanup
       cleaned = text.strip.gsub(/\s+/, ' ')
       Date.parse(cleaned) rescue nil
     }
```

```ruby
# Override the date extraction method for custom logic
def extract_date(doc, url)
  # custom logic here; return Date or nil
end
```