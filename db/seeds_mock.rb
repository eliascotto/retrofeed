# frozen_string_literal: true

require "zlib"

# =============================================================================
# Mock Seeds for Presentation Screenshots
# =============================================================================
#
# This file creates generic mock data for taking presentation screenshots.
# It populates the database with fake websites and articles that look realistic
# but are not connected to any real websites or content.
#
# WARNING: This is mock data intended for screenshots and demos only.
# Do not use in production.
#
# Usage:
#   bin/rails db:seed:mock
#
# This will reset the database and load the mock data.
#
# Extending this file:
# --------------------
# To add more websites, add entries to the WEBSITES array below.
# Articles are auto-generated based on the templates in ARTICLE_TEMPLATES.
# Each website gets 5-35 random articles, with at least 1 having full content.
# Favicons are auto-generated as colored circles based on the color field.
#
# =============================================================================

# Configuration
# =============================================================================

# Set the number of articles per website
NUMBER_OF_ARTICLES_PER_WEBSITE_MIN = 5
NUMBER_OF_ARTICLES_PER_WEBSITE_MAX = 57

puts "Loading mock data for presentation screenshots..."

# =============================================================================
# Favicon Generator
# =============================================================================
# Generates simple colored PNG favicons (32x32 pixels with solid color).

def hex_to_rgb(hex)
  hex = hex.delete("#")
  r = hex[0..1].to_i(16)
  g = hex[2..3].to_i(16)
  b = hex[4..5].to_i(16)
  [ r, g, b ]
end

def random_color
  # Generate a random bright color
  r = rand(100..255)
  g = rand(100..255)
  b = rand(100..255)
  [ r, g, b ]
end

def interpolate_color(color1, color2, ratio)
  # Interpolate between two colors
  # ratio: 0.0 = color1, 1.0 = color2
  r = (color1[0] * (1 - ratio) + color2[0] * ratio).round
  g = (color1[1] * (1 - ratio) + color2[1] * ratio).round
  b = (color1[2] * (1 - ratio) + color2[2] * ratio).round
  [ r, g, b ]
end

def generate_favicon_png(color1, color2)
  # Convert hex colors to RGB
  rgb1 = hex_to_rgb(color1)
  rgb2 = hex_to_rgb(color2)

  # Create a 32x32 PNG with circular gradient (RGBA for transparency)
  width = 32
  height = 32
  center_x = width / 2.0
  center_y = height / 2.0
  radius = width / 2.0 - 0.5 # Full circle

  # PNG signature (use dup to avoid frozen string error)
  png = "\x89PNG\r\n\x1a\n".dup.force_encoding("BINARY")

  # IHDR chunk (13 bytes data + 4 bytes CRC)
  # Color type 6 = RGBA (with alpha channel)
  ihdr_data = [ width, height, 8, 6, 0, 0, 0 ].pack("N2C5")
  ihdr_crc = Zlib.crc32("IHDR" + ihdr_data)
  png += [ 13 ].pack("N") + "IHDR" + ihdr_data + [ ihdr_crc ].pack("N")

  # IDAT chunk - create circular gradient image with transparency
  image_data = "".dup.force_encoding("BINARY")

  (0...height).each do |y|
    row = [ 0 ] # Filter byte (0 = none)

    (0...width).each do |x|
      # Calculate distance from center
      dx = x - center_x
      dy = y - center_y
      distance = Math.sqrt(dx * dx + dy * dy)

      if distance <= radius
        # Inside circle - apply gradient based on vertical position
        gradient_ratio = y.to_f / (height - 1)
        r, g, b = interpolate_color(rgb1, rgb2, gradient_ratio)
        alpha = 255 # Fully opaque
        row += [ r, g, b, alpha ]
      else
        # Outside circle - fully transparent
        row += [ 0, 0, 0, 0 ]
      end
    end

    image_data += row.pack("C*")
  end

  # Compress the image data
  compressed = Zlib::Deflate.deflate(image_data)
  idat_crc = Zlib.crc32("IDAT" + compressed)
  png += [ compressed.bytesize ].pack("N") + "IDAT" + compressed + [ idat_crc ].pack("N")

  # IEND chunk
  iend_crc = Zlib.crc32("IEND")
  png += [ 0 ].pack("N") + "IEND" + [ iend_crc ].pack("N")

  png
end

def attach_favicon(website, color1, color2)
  # Ensure website is saved first
  website.save! unless website.persisted?

  # Purge existing favicon first
  website.favicon.purge if website.favicon.attached?

  # Generate PNG favicon with gradient
  png_data = generate_favicon_png(color1, color2)

  # Attach new favicon
  website.favicon.attach(
    io: StringIO.new(png_data),
    filename: "favicon.png",
    content_type: "image/png"
  )

  # Ensure the attachment is saved
  website.save!

  # Reload to ensure favicon is available
  website.reload
end

# =============================================================================
# Websites
# =============================================================================
# Generic websites with varied themes and names.
# Each website represents a different type of blog/publication.
# Colors are used to generate unique solid-color favicons.

WEBSITES = [
  { domain: "techinsights.co",      name: "Tech Insights",       color: "#6366f1" },  # Indigo
  { domain: "designjournal.io",     name: "The Design Journal",  color: "#ec4899" },  # Pink
  { domain: "codecraft.com",         name: "Code Craft Weekly",   color: "#10b981" },  # Emerald
  { domain: "thoughtstream.dev",     name: "Thought Stream",      color: "#f59e0b" },  # Amber
  { domain: "devnotes.xyz",          name: "Dev Notes",           color: "#3b82f6" },  # Blue
  { domain: "pixelperfect.com",      name: "Pixel Perfect",       color: "#a855f7" },  # Purple
  { domain: "systemsthinking.com",   name: "Systems Thinking",    color: "#64748b" },  # Slate
  { domain: "frontendweekly.org",    name: "Frontend Weekly",     color: "#ef4444" },  # Red
  { domain: "datadigest.io",        name: "Data Digest",         color: "#06b6d4" },  # Cyan
  { domain: "buildlog.com",          name: "The Build Log",       color: "#22c55e" },  # Green
  { domain: "backendblog.com",       name: "Backend Blog",        color: "#f97316" },  # Orange
  { domain: "uxinsights.com",        name: "UX Insights",         color: "#8b5cf6" },  # Violet
  { domain: "devopsdaily.com",       name: "DevOps Daily",        color: "#14b8a6" },  # Teal
  { domain: "securitywatch.com",     name: "Security Watch",     color: "#dc2626" },  # Red-600
  { domain: "cloudchronicles.com",   name: "Cloud Chronicles",    color: "#0ea5e9" }   # Sky
].freeze

# =============================================================================
# Article Templates
# =============================================================================
# Templates for generating article titles. Each website will get a random
# selection of articles from these templates, adapted to sound natural.

ARTICLE_TITLES = [
  "Building Resilient Systems in the Modern Era",
  "The Art of Readable Code",
  "Scaling Infrastructure Without the Pain",
  "Why Simplicity Wins Every Time",
  "Lessons from a Decade of Debugging",
  "Principles of Visual Hierarchy",
  "Color Theory for Digital Interfaces",
  "Typography That Speaks",
  "Designing for Accessibility First",
  "The Psychology of User Interfaces",
  "Whitespace: The Invisible Element",
  "Functional Patterns in Practice",
  "Testing Strategies That Scale",
  "When to Reach for Abstractions",
  "The Case for Boring Technology",
  "The Value of Deliberate Practice",
  "Learning in Public",
  "On Taking Notes That Matter",
  "The Compound Effect of Small Habits",
  "Git Workflows for Solo Developers",
  "Mastering the Terminal",
  "Docker Without the Complexity",
  "Shell Scripts That Actually Work",
  "Setting Up a Development Environment",
  "CSS Grid Layouts Demystified",
  "Animation Principles for the Web",
  "Responsive Design Beyond Breakpoints",
  "Dark Mode Done Right",
  "Understanding Feedback Loops",
  "Complexity vs Complicated",
  "Mental Models for Engineers",
  "Second-Order Effects in Software",
  "State Management Patterns Compared",
  "Performance Budgets in Practice",
  "Component Libraries Worth Knowing",
  "The Future of CSS",
  "Accessibility Audits Made Simple",
  "Web Components in Production",
  "SQL Queries That Perform",
  "Data Modeling Best Practices",
  "Caching Strategies Explained",
  "When to Denormalize",
  "Shipping a Side Project",
  "Lessons from Building in Public",
  "The MVP Mindset",
  "Marketing for Developers",
  "Pricing Your Product",
  "Writing Documentation People Read",
  "API Design Principles",
  "Error Handling Done Right",
  "Logging That Actually Helps",
  "Monitoring Without Noise",
  "Database Migrations Without Fear",
  "Feature Flags in Practice",
  "A/B Testing for Engineers",
  "Technical Debt: When to Pay It",
  "Code Reviews That Work",
  "Pair Programming Patterns",
  "Remote Collaboration Tips",
  "Managing Technical Projects"
].freeze

# Full article content templates for the featured articles
FULL_ARTICLE_CONTENTS = [
  <<~HTML,
    <p>In today's rapidly evolving landscape, building systems that can withstand unexpected challenges has become more important than ever. This article explores the fundamental principles behind resilient architecture and how teams can implement them effectively.</p>
    <p>The key insight is that resilience isn't just about preventing failures. It's about designing systems that can adapt and recover when things inevitably go wrong. We'll examine how leading teams approach system design, focusing on redundancy, graceful degradation, and automated recovery mechanisms.</p>
    <h2>Understanding Failure Modes</h2>
    <p>Every system will eventually fail. The question is not if, but when and how. By understanding the most common failure modes, we can design systems that handle them gracefully rather than catastrophically.</p>
    <p>Consider the following scenarios: network partitions, disk failures, memory exhaustion, and cascading timeouts. Each requires a different strategy, but all share a common principle: expect failure and plan for it.</p>
    <h2>Building Blocks of Resilience</h2>
    <p>There are several patterns that have proven essential for building resilient systems:</p>
    <ul>
      <li><strong>Circuit Breakers</strong> - Prevent cascading failures by failing fast when a dependency is unhealthy</li>
      <li><strong>Bulkheads</strong> - Isolate components so that failure in one doesn't bring down the entire system</li>
      <li><strong>Retry with Backoff</strong> - Handle transient failures without overwhelming the system</li>
      <li><strong>Timeouts</strong> - Ensure that slow dependencies don't block the entire request path</li>
    </ul>
    <p>These patterns, when applied thoughtfully, create systems that bend rather than break under pressure.</p>
  HTML
  <<~HTML,
    <p>Code is read far more often than it is written. This simple observation has profound implications for how we approach software development. Clear, readable code isn't a luxury. It's a necessity for maintaining velocity over time.</p>
    <p>Good naming conventions, consistent formatting, and thoughtful organization all contribute to code that tells a story. When you return to code months later, you should be able to understand its purpose without extensive archaeology.</p>
    <h2>The Economics of Readability</h2>
    <p>Consider a codebase that will be maintained for five years. The initial writing might take a few weeks. But over those five years, dozens of engineers will read that code hundreds of times. Every minute saved in comprehension compounds dramatically.</p>
    <p>This is why investing in readability pays dividends. A function that takes an extra 10 minutes to write but saves 2 minutes of confusion each time it's read will pay for itself after just 5 readings.</p>
    <h2>Practical Guidelines</h2>
    <p>Here are some principles that consistently improve code readability:</p>
    <ul>
      <li><strong>Name things for what they represent</strong> - not for their type or implementation</li>
      <li><strong>Keep functions focused</strong> - each function should do one thing well</li>
      <li><strong>Avoid clever code</strong> - straightforward is almost always better than clever</li>
      <li><strong>Write comments that explain why</strong> - not what the code does, but why it does it</li>
    </ul>
    <p>The goal is to make the code's intent obvious. When intent is clear, bugs are easier to spot and changes are easier to make.</p>
  HTML
  <<~HTML,
    <p>Visual hierarchy is the cornerstone of effective design. It guides the viewer's eye through content in a deliberate, meaningful way. Without it, even the most beautiful designs fail to communicate their message.</p>
    <p>Size, color, contrast, and spacing all play crucial roles in establishing hierarchy. By understanding these relationships, designers can create interfaces that feel intuitive and effortless to navigate.</p>
    <h2>The Science of Attention</h2>
    <p>Our eyes are drawn to certain elements before others. Large elements before small. Bright colors before muted ones. High contrast before low contrast. Understanding these tendencies allows us to direct attention intentionally.</p>
    <p>The best hierarchies are invisible. Users don't notice them; they simply flow through the content naturally. This is the mark of thoughtful design.</p>
    <h2>Creating Effective Hierarchies</h2>
    <p>Start by identifying what's most important on each page or screen. This primary element should be unmistakably prominent. Then work backwards, establishing clear levels of importance for supporting content.</p>
    <p>Use these tools to create distinction between levels:</p>
    <ul>
      <li><strong>Scale</strong> - Larger elements command more attention</li>
      <li><strong>Weight</strong> - Bold text stands out from regular text</li>
      <li><strong>Color</strong> - Saturated colors attract the eye</li>
      <li><strong>Position</strong> - Elements at the top and left are seen first</li>
      <li><strong>Whitespace</strong> - Isolation draws attention to an element</li>
    </ul>
    <p>Remember: if everything is important, nothing is. Hierarchy requires making choices about what matters most.</p>
  HTML
  <<~HTML,
    <p>Functional programming concepts have permeated mainstream development. Even in traditionally object-oriented codebases, patterns like immutability, pure functions, and composition are becoming standard practice.</p>
    <p>This isn't about adopting a new paradigm wholesale. It's about incorporating proven techniques that lead to more predictable, testable code. Small changes in approach can yield significant improvements in code quality.</p>
    <h2>Why Functional Patterns Matter</h2>
    <p>The core benefit of functional patterns is predictability. A pure function with no side effects will always return the same output for the same input. This makes code easier to reason about, test, and debug.</p>
    <p>Immutability eliminates entire classes of bugs related to shared mutable state. When data cannot change unexpectedly, tracking down issues becomes much simpler.</p>
    <h2>Practical Applications</h2>
    <p>You don't need to use a functional language to benefit from these patterns. Here are ways to apply them in any codebase:</p>
    <ul>
      <li><strong>Prefer const over let</strong> - Default to immutability</li>
      <li><strong>Extract pure functions</strong> - Move logic that doesn't need side effects into pure functions</li>
      <li><strong>Use map, filter, reduce</strong> - These replace many imperative loops with declarative transforms</li>
      <li><strong>Compose small functions</strong> - Build complex behavior from simple, reusable pieces</li>
    </ul>
    <p>The goal isn't purity for its own sake. It's writing code that's easier to understand, test, and maintain.</p>
  HTML
  <<~HTML
    <p>Improvement doesn't happen by accident. Whether learning a new skill or refining an existing one, deliberate practice is the engine of growth. It requires focus, feedback, and a willingness to push beyond comfort zones.</p>
    <p>The difference between going through the motions and truly practicing lies in intentionality. Each session should have a specific goal, and progress should be measured and adjusted accordingly.</p>
    <h2>The Structure of Deliberate Practice</h2>
    <p>Deliberate practice has several key characteristics that distinguish it from mere repetition:</p>
    <ul>
      <li><strong>Specific goals</strong> - Each session targets a particular aspect of the skill</li>
      <li><strong>Full attention</strong> - Distracted practice is barely practice at all</li>
      <li><strong>Immediate feedback</strong> - You need to know when you're off track</li>
      <li><strong>Stretch zone</strong> - Practice just beyond your current ability</li>
    </ul>
    <p>This kind of practice is mentally demanding. It's not possible to maintain for hours on end. Short, focused sessions are more effective than long, unfocused ones.</p>
    <h2>Applying This to Software Development</h2>
    <p>For programmers, deliberate practice might mean working through coding challenges that target specific weaknesses. Or it might mean implementing a familiar algorithm in a new language to deepen understanding.</p>
    <p>The key is to be intentional. Identify what you want to improve, design practice that targets that area, and seek feedback on your progress. Growth compounds over time when approached systematically.</p>
  HTML
].freeze

# =============================================================================
# Create Websites and Articles
# =============================================================================

websites = {}
used_titles = Set.new

WEBSITES.each do |website_data|
  website = Website.find_or_create_by!(domain: website_data[:domain]) do |w|
    w.name              = website_data[:name]
    w.archive_url       = "https://#{website_data[:domain]}/archive"
    w.processing_status = "pending"
    w.last_crawled_at   = rand(1..7).days.ago
  end

  # Generate two random colors for gradient favicon
  color1_rgb = random_color
  color2_rgb = random_color
  color1 = "#%02x%02x%02x" % color1_rgb
  color2 = "#%02x%02x%02x" % color2_rgb

  # Always attach/update favicon to ensure it's saved and working
  attach_favicon(website, color1, color2)

  websites[website_data[:domain]] = website

  # Subscribe admin user to this website
  Subscription.find_or_create_by!(user: admin_user, website: website)

  puts "  Created website: #{website.name} (#{website.domain})"

  # Generate 5-35 articles for this website
  article_count = rand(NUMBER_OF_ARTICLES_PER_WEBSITE_MIN..NUMBER_OF_ARTICLES_PER_WEBSITE_MAX)
  available_titles = ARTICLE_TITLES - used_titles.to_a

  # If we don't have enough unique titles, allow reuse (realistic for mock data)
  if available_titles.size < article_count
    selected_titles = available_titles.sample(available_titles.size) + ARTICLE_TITLES.sample(article_count - available_titles.size)
  else
    selected_titles = available_titles.sample(article_count)
  end

  used_titles.merge(selected_titles)

  # All articles get the same full content from FULL_ARTICLE_CONTENTS
  full_content = FULL_ARTICLE_CONTENTS.sample

  selected_titles.each_with_index do |title, index|
    slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
    days_ago = rand(1..60)

    article = Article.find_or_create_by!(url: "https://#{website_data[:domain]}/#{slug}") do |a|
      a.website                 = website
      a.title                   = title
      a.slug                    = slug
      a.publication_date        = days_ago.days.ago.to_date
      a.content_html            = full_content
      a.word_count              = full_content.split.size
      a.last_content_fetched_at = rand(1..3).days.ago
    end

    puts "    Created article: #{article.title} (with full content)"
  end
end

# =============================================================================
# Summary
# =============================================================================

puts ""
puts "Mock data loaded successfully!"
puts "  Websites: #{Website.count}"
puts "  Articles: #{Article.count}"
puts "  Subscriptions: #{Subscription.count}"
puts ""
puts "Login with: admin@retrofeed.com / password123"
