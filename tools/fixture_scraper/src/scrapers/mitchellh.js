/**
 * Scraper for mitchellh.com
 * Archive format: links to /writing/ and /zig/ articles with date in gray div
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

  // Find all article links - both /writing/ and /zig/ paths
  $('a[href^="/writing/"], a[href^="/zig/"]').each((_, a) => {
    const elem = $(a);
    const href = elem.attr('href');
    if (!href) return;

    const link = resolveUrl(href, baseUrl);

    // Extract title from h1 inside the link
    const titleElem = elem.find('h1');
    if (!titleElem.length) return;

    const title = getText(titleElem);
    if (!title) return;

    // Extract date from div with gray text class
    let date = null;
    const dateDivs = elem.find('div').filter((_, div) => {
      const cls = $(div).attr('class') || '';
      return cls.includes('text-gray') || cls.includes('text-slate');
    });

    dateDivs.each((_, div) => {
      if (date) return;
      const dateText = getText($(div));
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

  // Content from main article area
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
