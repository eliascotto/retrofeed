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
  $('main a[href^="/"]').each((_, a) => {
    const elem = $(a);
    const href = elem.attr('href');

    // Skip non-article links
    if (!href || href === '/' || href.startsWith('/_next') ||
        href.startsWith('/icon') || href.startsWith('/avi')) {
      return;
    }

    const articleElem = elem.find('article');
    if (!articleElem.length) return;

    // Extract title from h2
    const titleElem = articleElem.find('h2');
    if (!titleElem.length) return;

    const title = getText(titleElem);
    if (!title) return;

    const link = resolveUrl(href, baseUrl);

    // Extract date from p with specific class
    let date = null;
    const dateParagraphs = articleElem.find('p').filter((_, p) => {
      const cls = $(p).attr('class') || '';
      return cls.includes('text-[13px]') || cls.includes('text-sm');
    });

    dateParagraphs.each((_, p) => {
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
  const $ = cheerio.load(html);

  // Title from h1
  const title = getText($('h1').first()) || getText($('title'));

  // Content from main or article
  const main = $('main').first();
  const article = $('article').first();
  const content = article.length ? article.html() : (main.length ? main.html() : $('body').html());

  // Date from time element or meta
  let date = null;
  const timeElem = $('time').first();
  if (timeElem.length) {
    const datetime = timeElem.attr('datetime') || getText(timeElem);
    date = parseDate(datetime);
  }

  return { title, content, date };
}
