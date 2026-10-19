# Archive Parsing Strategy Attempts

This document tracks various strategies attempted for extracting articles from blog archive pages.

---

## Failed/Deprecated Strategies

### 1. Semantic Strategy (Deprecated)

**File**: `app/services/web_processor/strategies/semantic_strategy.rb`

**Concept**: Extract articles by prioritizing semantic HTML5 elements and ARIA attributes.

**Algorithm**:
1. Phase 1 - Semantic Detection:
   - Look for `<article>` elements
   - Look for elements with `role="article"`
   - Look for schema.org BlogPosting (`[itemscope][itemtype*="BlogPosting"]`)

2. Phase 2 - Pattern Discovery (fallback if no semantic elements found):
   - Find article-like links (limited to first 50)
   - For each link, walk up DOM tree (up to 15 levels) to find best container
   - Score containers based on semantic indicators (article tag, headings, time elements)
   - Identify structural pattern from sample containers
   - Find all containers matching the pattern

3. Phase 3 - Validation and extraction:
   - Validate containers have links and content
   - Extract article data (title, URL, date, tags)
   - Sort by date

**Why it failed**:
- DOM tree walking is slow (O(n * depth)) 
- Max depth of 15 levels causes performance issues on complex pages
- Pattern identification relies on class name matching which varies across sites
- Poor accuracy on sites without semantic HTML

---

### 2. Link Clustering Strategy (Deprecated)

**File**: `app/services/web_processor/strategies/link_clustering_strategy.rb`

**Concept**: Extract articles by clustering links based on their container structure.

**Algorithm**:
1. Find all article-like links (limited to first 100)
2. For each link, walk up DOM tree (up to 15 levels) to find best container
3. Score containers based on:
   - Headings (h1-h4)
   - Date content (time elements, date classes, date patterns in text)
   - Semantic HTML (article, role="article")
   - Common blog class patterns (post, article, entry, item)
   - Proximity to link (prefer close ancestors)
4. Create structural signature for each container:
   - Tag name
   - Class pattern
   - ID pattern  
   - Parent tag
   - Number of direct children
5. Cluster containers by signature
6. Score each cluster (size + consistency)
7. Pick best cluster and extract articles

**Why it failed**:
- DOM tree walking for every link is O(n * depth) - very slow
- Structural signature generation is expensive
- Clustering adds overhead
- Performance degrades significantly on pages with many links
- Timeout issues on complex archives

---

### 3. Adaptive Strategy (Deprecated)

**File**: `app/services/web_processor/strategies/adaptive_strategy.rb`

**Concept**: Try multiple approaches and pick the best result.

**Algorithm**:
1. Try 5 sub-strategies in sequence:
   - **Semantic approach**: Look for `<article>`, `role="article"`, `main > article`
   - **List approach**: Find `<ul>/<ol>` with `<li>` items containing article links + headings/time
   - **Table approach**: Find `<table tr>` with title cells containing article links
   - **Link clustering**: Walk up DOM for each link, cluster by structure, pick largest cluster
   - **Generic containers**: CSS selectors like `[class*="post"]`, `[class*="article"]`

2. Score each result based on:
   - Number of containers
   - Consistency (all have headings, links, dates)

3. Pick best scoring result

**Why it failed**:
- Runs all strategies regardless of early success
- Link clustering sub-strategy still has DOM walking overhead
- No early exit optimization
- Combines slow approaches

---

## Proposed Strategies

### Proposal 1: Pattern-Based Container Discovery

**Concept**: Find the repeating container pattern by analyzing link groupings, not walking DOM trees.

**Algorithm**:
1. Find all article-like links (fast CSS query)
2. For each link, get its immediate parent (O(1), not walking up)
3. Group parents by structural signature (tag + class pattern)
4. The largest group with consistent structure = article containers
5. Extract from that group

**Performance**: O(n) where n = number of links (typically 20-100)

**Speed**: <100ms for most pages

**Accuracy**: High (finds repeating patterns)

**Pros**:
- Fast (no DOM traversal)
- Works for lists, divs, articles, tables
- Handles most archive structures

**Cons**:
- May miss nested structures
- Needs validation logic

---

### Proposal 4: Hybrid Fast Selectors + Smart Fallback

**Concept**: Combine fast CSS selectors with pattern-based discovery as fallback.

**Algorithm**:
1. Phase 1 - Try fast CSS selectors (in priority order):
   ```ruby
   SELECTORS = [
     "article",                    # Semantic HTML
     "ul.posts > li",             # Common list pattern
     "ul.post-archives > li",     # Another list pattern
     "main article",              # Main content area
     "main > a > article",        # Nested articles
     "table tr",                  # Table rows
     '[class*="post"]',           # Generic post classes
     '[class*="article"]',        # Generic article classes
   ]
   ```
   Validate results (has link + title), use first valid set with >= 3 articles

2. Phase 2 - Pattern discovery fallback (if no results):
   - Sample first 20 links
   - Get immediate parent of each (O(1))
   - Find most common parent pattern
   - Use that pattern to find ALL containers

3. Phase 3 - Last resort: direct link extraction

**Performance**: O(1) best case, O(20+n) worst case

**Speed**: <100ms best case, <300ms worst case

**Accuracy**: Very High (covers both common and custom)

**Pros**:
- Fast for common cases
- Handles edge cases via fallback
- Best of both worlds

**Cons**:
- More complex
- Still needs validation

**Expected Performance**:
- Common sites (overreacted, mitchellh): <50ms
- Complex sites (macwright, thinkingeek): <300ms
- Worst case: <800ms (still under 1 second)

