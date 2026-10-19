/**
 * Scraper for greydanus.github.io
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

    // Look for date pattern: "Mar 30, 2025"
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

  // Content from post-content or article
  const postContent = $('div.post-content').first();
  const article = $('article').first();
  const content = postContent.length ? postContent.html() : (article.length ? article.html() : $('body').html());

  // Date from URL pattern or meta
  let date = null;
  const urlMatch = url.match(/\/(\d{4})\/(\d{2})\/(\d{2})\//);
  if (urlMatch) {
    date = new Date(parseInt(urlMatch[1]), parseInt(urlMatch[2]) - 1, parseInt(urlMatch[3]));
  }

  return { title, content, date };
}
