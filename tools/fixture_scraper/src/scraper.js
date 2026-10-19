/**
 * Main scraper module
 * Provides high-level functions to scrape archives and articles
 */

import { WEBSITES } from './config.js';
import { getScraper } from './scrapers/index.js';
import { fetchPage, formatDateISO, resolveUrl } from './utils.js';
import { getRequestDelay, getUserAgent, getRequestTimeout } from './env.js';
import { generateArticleFilename } from './fixtures.js';
import * as cheerio from 'cheerio';

/**
 * Scrape archive page for a website
 * @param {string} websiteName - Name of the website (e.g., 'journal', 'mitchellh')
 * @param {object} options - Options
 * @param {string} [options.html] - Pre-fetched HTML (for testing)
 * @returns {Promise<{articles: Array<{title: string, link: string, date: string|null, tags: Array, order: number, file: string}>, html: string}>}
 */
export async function scrapeArchive(websiteName, options = {}) {
  const config = WEBSITES[websiteName];
  if (!config) {
    throw new Error(`Unknown website: ${websiteName}`);
  }

  const scraper = getScraper(websiteName);
  if (!scraper) {
    throw new Error(`No scraper found for website: ${websiteName}`);
  }

  // Fetch HTML if not provided
  const html = options.html || await fetchPage(config.url);

  // Parse archive
  const rawArticles = scraper.parseArchive(html, config.url);

  // Sort by date (oldest first) and assign order
  const articlesWithDate = rawArticles.filter((a) => a.date);
  const articlesWithoutDate = rawArticles.filter((a) => !a.date);

  articlesWithDate.sort((a, b) => a.date.getTime() - b.date.getTime());

  const allArticles = [...articlesWithDate, ...articlesWithoutDate];

  // Format output
  const articles = allArticles.map((art, idx) => {
    const dateStr = formatDateISO(art.date);
    const filename = generateArticleFilename(art.link, dateStr);
    return {
      title: art.title,
      link: art.link,
      date: dateStr,
      tags: art.tags,
      order: idx + 1,
      file: `articles/${filename}`,
    };
  });

  return { articles, html };
}

/**
 * Scrape a single article
 * @param {string} websiteName - Name of the website
 * @param {string} url - Article URL
 * @param {object} options - Options
 * @param {string} [options.html] - Pre-fetched HTML (for testing)
 * @returns {Promise<{title: string, content: string, date: string|null, html: string}>}
 */
export async function scrapeArticle(websiteName, url, options = {}) {
  const scraper = getScraper(websiteName);
  if (!scraper) {
    throw new Error(`No scraper found for website: ${websiteName}`);
  }

  // Fetch HTML if not provided
  const html = options.html || await fetchPage(url);

  // Parse article
  const { title, content, date } = scraper.parseArticle(html, url);

  return {
    title,
    content,
    date: formatDateISO(date),
    html,
  };
}

/**
 * Scrape all articles from a website archive
 * @param {string} websiteName - Name of the website
 * @param {object} options - Options
 * @param {number} [options.limit] - Limit number of articles to scrape
 * @param {number} [options.delay] - Delay between requests in ms (default from env)
 * @param {function} [options.onProgress] - Progress callback
 * @returns {Promise<Array<{title: string, link: string, date: string|null, content: string, html: string}>>}
 */
export async function scrapeAllArticles(websiteName, options = {}) {
  const { limit, onProgress } = options;
  const delay = options.delay ?? getRequestDelay();

  // First get the archive
  const { articles } = await scrapeArchive(websiteName);

  // Limit if specified
  const toScrape = limit ? articles.slice(0, limit) : articles;

  const results = [];
  for (let i = 0; i < toScrape.length; i++) {
    const article = toScrape[i];

    if (onProgress) {
      onProgress({
        current: i + 1,
        total: toScrape.length,
        article: article.title,
      });
    }

    try {
      const { title, content, date, html } = await scrapeArticle(websiteName, article.link);
      // Ensure file field is present (article already has it from scrapeArchive)
      results.push({
        ...article,
        title: title || article.title,
        content,
        date: date || article.date,
        html,
        file: article.file, // Preserve file path from archive
      });
    } catch (err) {
      console.error(`Failed to scrape ${article.link}: ${err.message}`);
      results.push({
        ...article,
        content: null,
        html: null,
        error: err.message,
        file: article.file, // Preserve file path even on error
      });
    }

    // Rate limit
    if (i < toScrape.length - 1 && delay > 0) {
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  return results;
}

/**
 * Scrape favicon for a website
 * @param {string} websiteName - Name of the website
 * @param {object} options - Options
 * @param {string} [options.html] - Pre-fetched HTML (for testing)
 * @param {string} [options.url] - Base URL to scrape favicon from (defaults to website config URL)
 * @returns {Promise<{faviconUrl: string|null, faviconData: Buffer|null}>}
 */
export async function scrapeFavicon(websiteName, options = {}) {
  const config = WEBSITES[websiteName];
  if (!config) {
    throw new Error(`Unknown website: ${websiteName}`);
  }

  const baseUrl = options.url || config.url;
  const html = options.html || await fetchPage(baseUrl);

  // Parse HTML to find favicon links
  const $ = cheerio.load(html);
  let faviconUrl = null;

  // Try to find favicon in <link> tags (priority order)
  const faviconSelectors = [
    'link[rel="icon"]',
    'link[rel="shortcut icon"]',
    'link[rel="apple-touch-icon"]',
    'link[rel="apple-touch-icon-precomposed"]',
  ];

  for (const selector of faviconSelectors) {
    const link = $(selector).first();
    if (link.length) {
      const href = link.attr('href');
      if (href) {
        faviconUrl = resolveUrl(href, baseUrl);
        break;
      }
    }
  }

  // Fallback to /favicon.ico if no link tag found
  if (!faviconUrl) {
    try {
      const faviconIcoUrl = new URL('/favicon.ico', baseUrl).href;
      // Try to fetch it to see if it exists
      const userAgent = getUserAgent();
      const timeout = getRequestTimeout();
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeout);

      try {
        const response = await fetch(faviconIcoUrl, {
          headers: {
            'User-Agent': userAgent,
          },
          signal: controller.signal,
        });
        if (response.ok) {
          faviconUrl = faviconIcoUrl;
        }
      } finally {
        clearTimeout(timeoutId);
      }
    } catch {
      // Ignore errors, will return null
    }
  }

  // Download favicon if found
  let faviconData = null;
  if (faviconUrl) {
    try {
      const userAgent = getUserAgent();
      const timeout = getRequestTimeout();
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeout);

      try {
        const response = await fetch(faviconUrl, {
          headers: {
            'User-Agent': userAgent,
          },
          signal: controller.signal,
        });
        if (response.ok) {
          const arrayBuffer = await response.arrayBuffer();
          faviconData = Buffer.from(arrayBuffer);
        }
      } finally {
        clearTimeout(timeoutId);
      }
    } catch (err) {
      console.warn(`Failed to download favicon from ${faviconUrl}: ${err.message}`);
    }
  }

  return {
    faviconUrl,
    faviconData,
  };
}
