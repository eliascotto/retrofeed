import { describe, it } from 'node:test';
import assert from 'node:assert';
import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseArchive as parseJournal } from '../src/scrapers/journal.js';
import { parseArchive as parseMitchellh } from '../src/scrapers/mitchellh.js';
import { parseArchive as parseMacwright } from '../src/scrapers/macwright.js';
import { parseArchive as parseOverreacted } from '../src/scrapers/overreacted.js';
import { parseArchive as parseThinkingeek } from '../src/scrapers/thinkingeek.js';
import { parseArchive as parseGreydanus } from '../src/scrapers/greydanus.js';
import { parseArchive as parseLisper } from '../src/scrapers/lisper.js';
import { parseArchive as parsePaulgraham } from '../src/scrapers/paulgraham.js';
import { parseArchive as parseMarijnhaverbeke } from '../src/scrapers/marijnhaverbeke.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
// __dirname = lib/scrapers/test -> go up 3 levels to project root
const fixturesDir = join(__dirname, '..', '..', '..', 'test', 'fixtures', 'websites');

async function loadFixture(website) {
  const htmlPath = join(fixturesDir, website, 'archive.html');
  const jsonPath = join(fixturesDir, website, 'archive.json');

  try {
    const [html, jsonStr] = await Promise.all([
      readFile(htmlPath, 'utf-8'),
      readFile(jsonPath, 'utf-8').catch(() => null),
    ]);

    return {
      html,
      expected: jsonStr ? JSON.parse(jsonStr) : null,
    };
  } catch {
    return { html: null, expected: null };
  }
}

describe('journal scraper', () => {
  it('parses archive correctly', async () => {
    const { html, expected } = await loadFixture('journal');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parseJournal(html, 'https://journal.stuffwithstuff.com/archive/');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');

    if (expected) {
      assert.strictEqual(articles.length, expected.length, 'Should match expected count');
    }
  });
});

describe('mitchellh scraper', () => {
  it('parses archive correctly', async () => {
    const { html, expected } = await loadFixture('mitchellh');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parseMitchellh(html, 'https://mitchellh.com/writing');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');
  });
});

describe('macwright scraper', () => {
  it('parses archive correctly', async () => {
    const { html, expected } = await loadFixture('macwright');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parseMacwright(html, 'https://macwright.com/writing');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');

    if (expected) {
      assert.strictEqual(articles.length, expected.length, 'Should match expected count');
    }
  });
});

describe('overreacted scraper', () => {
  it('parses archive correctly', async () => {
    const { html, expected } = await loadFixture('overreacted');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parseOverreacted(html, 'https://overreacted.io/');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');

    if (expected) {
      assert.strictEqual(articles.length, expected.length, 'Should match expected count');
    }
  });
});

describe('thinkingeek scraper', () => {
  it('parses archive correctly', async () => {
    const { html } = await loadFixture('thinkingeek');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parseThinkingeek(html, 'https://thinkingeek.com/archives/');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');
  });
});

describe('greydanus scraper', () => {
  it('parses archive correctly', async () => {
    const { html, expected } = await loadFixture('greydanus');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parseGreydanus(html, 'https://greydanus.github.io/');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');

    if (expected) {
      assert.strictEqual(articles.length, expected.length, 'Should match expected count');
    }
  });
});

describe('lisper scraper', () => {
  it('parses archive correctly', async () => {
    const { html, expected } = await loadFixture('lisper');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parseLisper(html, 'https://overreacted.io/');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');

    if (expected) {
      assert.strictEqual(articles.length, expected.length, 'Should match expected count');
    }
  });
});

describe('paulgraham scraper', () => {
  it('parses archive correctly', async () => {
    const { html } = await loadFixture('paulgraham');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parsePaulgraham(html, 'https://www.paulgraham.com/articles.html');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');
  });
});

describe('marijnhaverbeke scraper', () => {
  it('parses archive correctly', async () => {
    const { html } = await loadFixture('marijnhaverbeke');
    if (!html) {
      console.log('  Skipping: no fixture file');
      return;
    }

    const articles = parseMarijnhaverbeke(html, 'https://marijnhaverbeke.nl/blog/');

    assert.ok(articles.length > 0, 'Should find articles');
    assert.ok(articles[0].title, 'Articles should have titles');
    assert.ok(articles[0].link, 'Articles should have links');
  });
});
