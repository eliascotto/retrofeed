/**
 * Scraper for hawksley
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
  $('ul.posts li').each((_, cont) => {
    const elem = $(cont)
    const linkEl = elem.find("a")
    const href = linkEl.attr('href');

    const title = getText(linkEl);
    if (!title) return;

    const link = resolveUrl(href, baseUrl);

    // Extract date from p with specific class
    const dateEl = elem.find("date")
    const dateTime = getText(dateEl)
    const date = parseDate(dateTime) || null

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
