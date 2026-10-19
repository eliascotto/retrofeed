# @retrofeed/scrapers

Blog archive and article scrapers for Retrofeed.

## Installation

```bash
cd lib/scrapers
npm install
```

## Usage

### CLI

```bash
# List available websites
npm run scrape list

# Scrape archive and save fixtures (includes favicon by default)
npm run scrape archive paulgraham

# Scrape only favicon (skip archive scraping)
npm run scrape archive paulgraham --favicon

# Scrape archives for all websites
npm run scrape archive-all

# Scrape favicons for all websites
npm run scrape archive-all --favicon

# Scrape all articles for a website
npm run scrape articles paulgraham --limit 10

# Scrape articles skipping existing fixtures
npm run scrape articles paulgraham --skip-existing

# Scrape a single article
npm run scrape article paulgraham https://paulgraham.com/some-post/

# Check fixture status
npm run scrape status paulgraham
npm run scrape status-all
```

### Programmatic

```javascript
import { scrapeArchive, scrapeArticle } from '@retrofeed/scrapers';

// Scrape an archive
const { articles, html } = await scrapeArchive('journal');

// Scrape a single article
const { title, content, date, html } = await scrapeArticle(
  'journal',
  'https://journal.stuffwithstuff.com/2025/01/01/some-post/'
);
```

## Adding a New Website

1. Create a new scraper in `src/scrapers/<name>.js`:

```javascript
import * as cheerio from 'cheerio';
import { parseDate, resolveUrl, getText } from '../utils.js';

export function parseArchive(html, baseUrl) {
  const $ = cheerio.load(html);
  const articles = [];

  // Parse the archive HTML and extract articles
  // Each article should have: { title, link, date, tags }

  return articles;
}

export function parseArticle(html, url) {
  const $ = cheerio.load(html);

  // Parse the article HTML
  // Return: { title, content, date }

  return { title, content, date };
}
```

2. Register in `src/scrapers/index.js`:

```javascript
import * as newsite from './newsite.js';

export const scrapers = {
  // ... existing
  newsite,
};
```

3. Add config in `src/config.js`:

```javascript
export const WEBSITES = {
  // ... existing
  newsite: {
    name: 'newsite',
    url: 'https://example.com/archive/',
    description: 'Description of the site',
  },
};
```

4. Add tests in `test/scrapers.test.js`

## Configuration

Copy `.env.example` to `.env` and customize as needed:

```bash
cp .env.example .env
```

Available settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `FIXTURES_DIR` | `lib/scrapers/fixtures-output` | Output directory for fixtures |
| `REQUEST_DELAY_MIN` | `500` | Minimum delay between requests (ms) |
| `REQUEST_DELAY_MAX` | `3000` | Maximum delay between requests (ms) |
| `REQUEST_TIMEOUT` | `30000` | Request timeout (ms) |
| `USER_AGENT` | Retrofeed/1.0 | HTTP User-Agent string |
| `MAX_CONCURRENT` | `1` | Max concurrent requests |
| `VERBOSE` | `false` | Enable verbose logging |

View current config:

```bash
npm run scrape config
```

## Testing

```bash
npm test
npm run test:watch
```

## Supported Websites

| Name            | URL                                         | Has Tags |
|-----------------|---------------------------------------------|----------|
| journal         | journal.stuffwithstuff.com                  | Yes      |
| mitchellh       | mitchellh.com                               | No       |
| macwright       | macwright.com                               | No       |
| overreacted     | overreacted.io                              | No       |
| thinkingeek     | thinkingeek.com                             | Yes      |
| greydanus       | greydanus.github.io                         | No       |
| lisper          | lisper.in                                   | No       |
| paulgraham      | paulgraham.com                              | No       |
| marijnhaverbeke | marijnhaverbeke.nl                          | Yes      |
