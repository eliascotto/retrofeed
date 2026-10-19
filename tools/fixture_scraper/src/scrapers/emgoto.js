/**
 * Scraper for overreacted.io
 * Archive format: main > a[href^="/"] with article > h2 and p.date
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

  // Find all links in main that point to articles
  $('#posts-list a.post-card').each((_, a) => {
    const elem = $(a);
    const href = elem.attr('href');

    const articleElem = elem.find('.post-card-content');
    if (!articleElem.length) return;

    // Extract title from h2
    const titleElem = articleElem.find('.post-card-header h3');
    if (!titleElem.length) return;

    const title = getText(titleElem);
    if (!title) return;

    const link = resolveUrl(href, baseUrl);

    // Extract date from p with specific class
    let date = null;
    articleElem.find('.post-card-date').each((_, p) => {
      if (date) return;
      const dateText = getText($(p));
      date = parseDate(dateText);
    });

    articles.push({ title, link, date, tags: [] });
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
  // Not implemented yet
  return { title: '', content: '', date: null };
}
