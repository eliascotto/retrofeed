/**
 * Fixture management for test data
 */

import { mkdir, writeFile, readFile, readdir, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { getFixturesBasePath } from './env.js';
import { extname } from 'node:path';

/**
 * Get the fixtures directory path for a website
 * @param {string} websiteName
 * @returns {string}
 */
export function getFixturesDir(websiteName) {
  return join(getFixturesBasePath(), websiteName);
}

/**
 * Save archive fixtures (HTML and JSON)
 * @param {string} websiteName
 * @param {Array} articles
 * @param {string} html
 */
export async function saveArchiveFixtures(websiteName, articles, html) {
  const dir = getFixturesDir(websiteName);
  await mkdir(dir, { recursive: true });

  // Save HTML
  const htmlPath = join(dir, 'archive.html');
  await writeFile(htmlPath, html, 'utf-8');

  // Save JSON
  const jsonPath = join(dir, 'archive.json');
  await writeFile(jsonPath, JSON.stringify(articles, null, 2), 'utf-8');

  return { htmlPath, jsonPath };
}

/**
 * Save article fixture (HTML file)
 * @param {string} websiteName
 * @param {string} articleUrl
 * @param {string} html
 * @param {string} [date] - Optional date for filename
 * @returns {Promise<string>} - Path to saved file
 */
export async function saveArticleFixture(websiteName, articleUrl, html, date) {
  const dir = join(getFixturesDir(websiteName), 'articles');
  await mkdir(dir, { recursive: true });

  // Generate filename from URL
  const filename = generateArticleFilename(articleUrl, date);
  const filePath = join(dir, filename);

  await writeFile(filePath, html, 'utf-8');

  return filePath;
}

/**
 * Generate a filename for an article based on its URL and date
 * @param {string} url
 * @param {string} [date] - ISO date string (YYYY-MM-DD)
 * @returns {string}
 */
export function generateArticleFilename(url, date) {
  // Extract slug from URL
  const urlObj = new URL(url);
  let slug = urlObj.pathname
    .replace(/^\//, '') // Remove leading slash
    .replace(/\/$/, '') // Remove trailing slash
    .replace(/\.html$/, '') // Remove .html extension
    .replace(/\//g, '-'); // Replace slashes with dashes

  // If we have a date, prefix with it
  if (date && !slug.startsWith(date)) {
    slug = `${date}-${slug}`;
  }

  // Ensure .html extension
  if (!slug.endsWith('.html')) {
    slug = `${slug}.html`;
  }

  // Sanitize filename
  slug = slug.replace(/[^a-zA-Z0-9._-]/g, '-').replace(/-+/g, '-');

  return slug;
}

/**
 * Load existing archive fixtures
 * @param {string} websiteName
 * @returns {Promise<{articles: Array|null, html: string|null}>}
 */
export async function loadArchiveFixtures(websiteName) {
  const dir = getFixturesDir(websiteName);

  try {
    const [html, json] = await Promise.all([
      readFile(join(dir, 'archive.html'), 'utf-8').catch(() => null),
      readFile(join(dir, 'archive.json'), 'utf-8').catch(() => null),
    ]);

    return {
      html,
      articles: json ? JSON.parse(json) : null,
    };
  } catch {
    return { html: null, articles: null };
  }
}

/**
 * List existing article fixtures for a website
 * @param {string} websiteName
 * @returns {Promise<string[]>}
 */
export async function listArticleFixtures(websiteName) {
  const dir = join(getFixturesDir(websiteName), 'articles');

  try {
    const files = await readdir(dir);
    return files.filter((f) => f.endsWith('.html'));
  } catch {
    return [];
  }
}

/**
 * Check if an article fixture exists
 * @param {string} websiteName
 * @param {string} filename
 * @returns {Promise<boolean>}
 */
export async function articleFixtureExists(websiteName, filename) {
  const filePath = join(getFixturesDir(websiteName), 'articles', filename);

  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

/**
 * Save favicon for a website
 * @param {string} websiteName
 * @param {Buffer} faviconData - Favicon file data
 * @param {string} [faviconUrl] - Original favicon URL (for determining extension)
 * @returns {Promise<string>} - Path to saved file
 */
export async function saveFavicon(websiteName, faviconData, faviconUrl = null) {
  const dir = getFixturesDir(websiteName);
  await mkdir(dir, { recursive: true });

  // Determine file extension from URL or default to .ico
  let extension = '.ico';
  if (faviconUrl) {
    try {
      const url = new URL(faviconUrl);
      const pathname = url.pathname;
      const ext = extname(pathname);
      if (ext && ['.ico', '.png', '.svg', '.jpg', '.jpeg', '.webp'].includes(ext.toLowerCase())) {
        extension = ext.toLowerCase();
      }
    } catch {
      // Use default .ico if URL parsing fails
    }
  }

  const filename = `favicon${extension}`;
  const filePath = join(dir, filename);

  await writeFile(filePath, faviconData);

  return filePath;
}

/**
 * Save all fixtures (archive + articles)
 * Convenience function that saves everything
 */
export async function saveFixtures(websiteName, archiveData, articlesData = []) {
  const { articles, html } = archiveData;

  // Save archive
  const archivePaths = await saveArchiveFixtures(websiteName, articles, html);

  // Save articles
  const articlePaths = [];
  for (const article of articlesData) {
    if (article.html) {
      const path = await saveArticleFixture(
        websiteName,
        article.link,
        article.html,
        article.date
      );
      articlePaths.push(path);
    }
  }

  return {
    archive: archivePaths,
    articles: articlePaths,
  };
}
