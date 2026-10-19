/**
 * Scraper for lisper.in
 * Archive format: li elements with date pattern and links
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

  $('li').each((_, li) => {
    const elem = $(li);
    const text = getText(elem);
    if (!text) return;

    // Look for date pattern: "Mar 14, 2022"
    const dateMatch = text.match(/([A-Za-z]{3})\s+(\d{1,2}),\s+(\d{4})/);
    if (!dateMatch) return;

    const date = parseDate(`${dateMatch[1]} ${dateMatch[2]}, ${dateMatch[3]}`);
    if (!date) return;

    // Find the link in this list item
    const linkElem = elem.find('a[href]').first();
    if (!linkElem.length) return;

    const title = getText(linkElem);
    const href = linkElem.attr('href');
    if (!title || !href) return;

    const link = resolveUrl(href, baseUrl);

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
  const $ = cheerio.load(html);

  // Title from h1 or title tag
  const title = getText($('h1').first()) || getText($('title'));

  // Content from main content area
  const article = $('article').first();
  const main = $('main').first();
  const content = article.length ? article.html() : (main.length ? main.html() : $('body').html());

  // Date from meta or page content
  let date = null;
  const metaDate = $('meta[property="article:published_time"]').attr('content');
  if (metaDate) {
    date = parseDate(metaDate);
  }

  return { title, content, date };
}
