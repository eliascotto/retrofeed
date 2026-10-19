/**
 * Scraper for journal.stuffwithstuff.com
 * Archive format: table-based with date, title, tags columns
 */

import * as cheerio from 'cheerio';
import { parseDate, resolveUrl, getText } from '../utils.js';

const MONTHS = {
  Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
  Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11,
};

/**
 * Parse the archive page
 * @param {string} html - HTML content
 * @param {string} baseUrl - Base URL for resolving links
 * @returns {Array<{title: string, link: string, date: Date|null, tags: string[]}>}
 */
export function parseArchive(html, baseUrl) {
  const $ = cheerio.load(html);
  const articles = [];

  const table = $('table');
  if (!table.length) {
    throw new Error('Could not find archive table on the page');
  }

  let currentYear = null;

  table.find('tr').each((i, tr) => {
    // Skip header row
    if (i === 0) return;

    const tds = $(tr).find('td');
    if (tds.length < 3) return;

    const dateCell = $(tds[0]);
    const titleCell = $(tds[1]);
    const tagsCell = $(tds[2]);

    // Parse date
    const dateText = getText(dateCell);
    if (!dateText || dateText.toLowerCase().startsWith('date')) return;

    const parts = dateText.split(/\s+/);
    let date = null;

    // Format: "2025 Jul 13" or "May 30" (same year)
    if (parts.length === 3 && /^\d{4}$/.test(parts[0])) {
      currentYear = parseInt(parts[0]);
      const month = MONTHS[parts[1]];
      const day = parseInt(parts[2]);
      if (month !== undefined && !isNaN(day)) {
        date = new Date(currentYear, month, day);
      }
    } else if (parts.length === 2 && currentYear !== null) {
      const month = MONTHS[parts[0]];
      const day = parseInt(parts[1]);
      if (month !== undefined && !isNaN(day)) {
        date = new Date(currentYear, month, day);
      }
    }

    if (!date) return;

    // Parse title and link
    const titleLink = titleCell.find('a');
    if (!titleLink.length) return;

    const title = getText(titleLink);
    const href = titleLink.attr('href');
    if (!title || !href) return;

    const link = resolveUrl(href, baseUrl);

    // Parse tags
    const tags = [];
    tagsCell.find('a').each((_, a) => {
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
  const title = getText($('article h1').first()) || getText($('h1').first()) || getText($('title'));

  // Content from article body
  const article = $('article').first();
  const content = article.length ? article.html() : $('body').html();

  // Date from meta or URL pattern
  let date = null;
  const urlMatch = url.match(/\/(\d{4})\/(\d{2})\/(\d{2})\//);
  if (urlMatch) {
    date = new Date(parseInt(urlMatch[1]), parseInt(urlMatch[2]) - 1, parseInt(urlMatch[3]));
  }

  return { title, content, date };
}
