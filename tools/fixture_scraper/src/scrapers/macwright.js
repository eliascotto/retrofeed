/**
 * Scraper for macwright.com
 * Archive format: div.writing with title links followed by time elements
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

  const writingDiv = $('div.writing');
  if (!writingDiv.length) {
    return articles;
  }

  // Get all children to process div/time pairs
  const children = writingDiv.children().toArray();

  let i = 0;
  while (i < children.length) {
    const child = $(children[i]);

    if (child.is('div')) {
      const linkElem = child.find('a[href]');
      if (linkElem.length) {
        const title = getText(linkElem);
        const href = linkElem.attr('href');

        if (title && href) {
          const link = resolveUrl(href, baseUrl);
          let date = null;

          // Next sibling should be a time element
          if (i + 1 < children.length) {
            const nextChild = $(children[i + 1]);
            if (nextChild.is('time')) {
              const dateText = getText(nextChild);
              date = parseDate(dateText);
              i++; // Skip the time element
            }
          }

          articles.push({ title, link, date, tags: [] });
        }
      }
    }

    i++;
  }

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

  // Title from h1
  const title = getText($('h1').first()) || getText($('title'));

  // Content from article
  const article = $('article').first();
  const content = article.length ? article.html() : $('body').html();

  // Date from time element or URL
  let date = null;
  const timeElem = $('time').first();
  if (timeElem.length) {
    const datetime = timeElem.attr('datetime') || getText(timeElem);
    date = parseDate(datetime);
  }

  // Fallback: URL pattern /YYYY/MM/DD/
  if (!date) {
    const urlMatch = url.match(/\/(\d{4})\/(\d{2})\/(\d{2})\//);
    if (urlMatch) {
      date = new Date(parseInt(urlMatch[1]), parseInt(urlMatch[2]) - 1, parseInt(urlMatch[3]));
    }
  }

  return { title, content, date };
}
