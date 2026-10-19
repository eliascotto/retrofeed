/**
 * Scraper for paulgraham.com
 * Archive format: table-based layout with links to .html articles
 */

import * as cheerio from 'cheerio';
import { resolveUrl, normalizeWhitespace } from '../utils.js';

/**
 * Parse the archive page
 * @param {string} html - HTML content
 * @param {string} baseUrl - Base URL for resolving links
 * @returns {Array<{title: string, link: string, date: Date|null, tags: string[]}>}
 */
export function parseArchive(html, baseUrl) {
  const $ = cheerio.load(html);
  const articles = [];
  const seenTitles = new Set();

  // Find the container table (same selector as custom_rules.rb)
  let container = $('html body table tbody tr td table');
  if (!container.length) {
    container = $('body');
  }

  container.find('a[href]').each((_, a) => {
    const elem = $(a);
    const href = (elem.attr('href') || '').trim();
    let title = normalizeWhitespace(elem.text());

    // Skip if no title or href
    if (!title || !href) return;

    // Accept .html articles and .txt files
    if (!href.endsWith('.html') && !href.endsWith('.txt') && !href.includes('.txt?')) {
      return;
    }

    // Skip main page and non-article pages
    const skipPages = ['articles.html', 'index.html', 'rss.html'];
    if (skipPages.includes(href)) return;

    // Skip RSS/feed links
    if (['rss', 'feed', 'atom'].includes(title.toLowerCase())) return;

    // Skip image-only links
    if (title.length < 2) return;

    // Skip duplicates
    if (seenTitles.has(title)) return;
    seenTitles.add(title);

    // Build full URL
    const link = href.startsWith('http') ? href : resolveUrl(href, baseUrl);

    // Paul Graham's site doesn't show dates in listing
    articles.push({ title, link, date: null, tags: [] });
  });

  return articles;
}

/**
 * Parse article content
 * @param {string} html - HTML content
 * @param {string} url - Article URL
 * @returns {{title: string, content: string, date: Date|null}}
 */
export function parseArticle(html, url) {
  const $ = cheerio.load(html);

  // Title from title tag (Paul Graham uses simple HTML)
  const title = normalizeWhitespace($('title').text()) || '';

  // Content - Paul Graham uses table-based layout
  // Try to find main content table
  const tables = $('table');
  let content = '';

  if (tables.length > 1) {
    // Usually the second table contains the essay
    content = $(tables[1]).html() || '';
  }

  if (!content) {
    content = $('body').html() || '';
  }

  // Paul Graham rarely shows dates on articles
  return { title, content, date: null };
}
