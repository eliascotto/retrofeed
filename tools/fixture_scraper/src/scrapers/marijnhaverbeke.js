/**
 * Scraper for marijnhaverbeke.nl/blog/
 * Archive format: div.post with h2 > a title, span.date for date, span.tag for tags
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

  $('div.post').each((_, post) => {
    const elem = $(post);

    // Extract title and link from h2 > a
    const titleLink = elem.find('h2 > a').first();
    if (!titleLink.length) return;

    const title = getText(titleLink);
    const href = titleLink.attr('href');
    if (!title || !href) return;

    const link = resolveUrl(href, baseUrl);

    // Extract date from span.date
    let date = null;
    const dateElem = elem.find('span.date').first();
    if (dateElem.length) {
      let dateText = getText(dateElem);
      // Format: "Tuesday, September 30, 2025" - remove day of week
      if (dateText.includes(', ')) {
        const parts = dateText.split(', ');
        if (parts.length >= 2) {
          dateText = parts.slice(1).join(', ');
        }
      }
      date = parseDate(dateText);
    }

    // Extract tags from span.tag elements
    const tags = [];
    elem.find('span.tag').each((_, tag) => {
      const tagText = getText($(tag));
      if (tagText) tags.push(tagText);
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
  const title = getText($('h1').first()) || getText($('title'));

  // Content from article or main content area
  const article = $('article').first();
  const post = $('div.post').first();
  const content = article.length ? article.html() : (post.length ? post.html() : $('body').html());

  // Date from span.date
  let date = null;
  const dateElem = $('span.date').first();
  if (dateElem.length) {
    let dateText = getText(dateElem);
    if (dateText.includes(', ')) {
      const parts = dateText.split(', ');
      if (parts.length >= 2) {
        dateText = parts.slice(1).join(', ');
      }
    }
    date = parseDate(dateText);
  }

  return { title, content, date };
}
