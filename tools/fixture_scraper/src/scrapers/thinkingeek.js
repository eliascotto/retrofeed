/**
 * Scraper for thinkingeek.com
 * Archive format: ul.post-archives > li with post-meta span and h2 > a.post-link
 */

import * as cheerio from 'cheerio';
import { parseDate, resolveUrl, getText } from '../utils.js';

/**
 * Parse the archive page
 * @param {string} html - HTML content
 * @param {string} baseUrl - Base URL for resolving links
 * @returns {Array<{title: string, link: string, date: Date|null, tags: string[]}>}
 */
export function parseArchive(html, baseUrl) {
  const $ = cheerio.load(html);
  const articles = [];

  $('ul.post-archives > li').each((_, li) => {
    const elem = $(li);

    // Extract title and link from h2 > a.post-link
    const titleLink = elem.find('h2 a.post-link');
    if (!titleLink.length) return;

    const title = getText(titleLink);
    const href = titleLink.attr('href');
    if (!title || !href) return;

    const link = resolveUrl(href, baseUrl);

    // Extract date from post-meta span
    let date = null;
    const metaSpan = elem.find('span.post-meta');
    if (metaSpan.length) {
      const metaText = getText(metaSpan);
      // Format: "Aug 13, 2025 • ..."
      const dateMatch = metaText.match(/([A-Za-z]{3})\s+(\d{1,2}),\s+(\d{4})/);
      if (dateMatch) {
        date = parseDate(`${dateMatch[1]} ${dateMatch[2]}, ${dateMatch[3]}`);
      }
    }

    // Extract tags/categories
    const tags = [];
    elem.find('a[href*="/categories/"]').each((_, a) => {
      const tag = getText($(a));
      if (tag) tags.push(tag);
    });

    articles.push({ title, link, date, tags });
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

  // Title from h1 or title tag
  const title = getText($('h1.post-title').first()) || getText($('h1').first()) || getText($('title'));

  // Content from post-content div
  const postContent = $('div.post-content').first();
  const article = $('article').first();
  const content = postContent.length ? postContent.html() : (article.length ? article.html() : $('body').html());

  // Date from post-meta or URL
  let date = null;
  const metaSpan = $('span.post-meta').first();
  if (metaSpan.length) {
    const metaText = getText(metaSpan);
    const dateMatch = metaText.match(/([A-Za-z]{3})\s+(\d{1,2}),\s+(\d{4})/);
    if (dateMatch) {
      date = parseDate(`${dateMatch[1]} ${dateMatch[2]}, ${dateMatch[3]}`);
    }
  }

  return { title, content, date };
}
