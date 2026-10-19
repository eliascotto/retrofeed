/**
 * Utility functions for scrapers
 */

/**
 * Parse a date string into a Date object
 * Tries multiple common date formats
 * @param {string} dateStr - Date string to parse
 * @returns {Date|null}
 */
export function parseDate(dateStr) {
  if (!dateStr) return null;

  const str = dateStr.trim();

  // ISO format: 2025-12-01
  const isoMatch = str.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (isoMatch) {
    return new Date(parseInt(isoMatch[1]), parseInt(isoMatch[2]) - 1, parseInt(isoMatch[3]));
  }

  // Full month format: December 1, 2025 or December 01, 2025
  const fullMonthMatch = str.match(/^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$/);
  if (fullMonthMatch) {
    const date = new Date(`${fullMonthMatch[1]} ${fullMonthMatch[2]}, ${fullMonthMatch[3]}`);
    if (!isNaN(date.getTime())) return date;
  }

  // Abbreviated month: Dec 1, 2025 or Dec 01, 2025
  const abbrevMatch = str.match(/^([A-Za-z]{3})\s+(\d{1,2}),?\s+(\d{4})$/);
  if (abbrevMatch) {
    const date = new Date(`${abbrevMatch[1]} ${abbrevMatch[2]}, ${abbrevMatch[3]}`);
    if (!isNaN(date.getTime())) return date;
  }

  // Day of week prefix: Tuesday, September 30, 2025
  const dayOfWeekMatch = str.match(/^[A-Za-z]+,\s+(.+)$/);
  if (dayOfWeekMatch) {
    return parseDate(dayOfWeekMatch[1]);
  }

  // Try native parsing as fallback
  const fallback = new Date(str);
  if (!isNaN(fallback.getTime())) return fallback;

  return null;
}

/**
 * Format a Date object to ISO date string (YYYY-MM-DD)
 * @param {Date} date
 * @returns {string}
 */
export function formatDateISO(date) {
  if (!date) return null;
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Resolve a relative URL against a base URL
 * @param {string} href - Relative or absolute URL
 * @param {string} baseUrl - Base URL
 * @returns {string}
 */
export function resolveUrl(href, baseUrl) {
  if (!href) return '';
  try {
    return new URL(href, baseUrl).href;
  } catch {
    return href;
  }
}

/**
 * Normalize whitespace in a string
 * @param {string} str
 * @returns {string}
 */
export function normalizeWhitespace(str) {
  if (!str) return '';
  return str.replace(/\s+/g, ' ').trim();
}

/**
 * Extract text content from a Cheerio element, normalized
 * @param {import('cheerio').Cheerio} elem
 * @returns {string}
 */
export function getText(elem) {
  if (!elem || !elem.length) return '';
  return normalizeWhitespace(elem.text());
}

/**
 * Fetch a URL with proper headers
 * @param {string} url
 * @param {object} [options]
 * @param {string} [options.userAgent]
 * @param {number} [options.timeout]
 * @returns {Promise<string>}
 */
export async function fetchPage(url, options = {}) {
  // Import env config lazily to avoid circular deps
  const { getUserAgent, getRequestTimeout } = await import('./env.js');

  const userAgent = options.userAgent || getUserAgent();
  const timeout = options.timeout || getRequestTimeout();

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(url, {
      headers: {
        'User-Agent': userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch ${url}: ${response.status} ${response.statusText}`);
    }

    return response.text();
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Sleep for a given number of milliseconds
 * @param {number} ms
 * @returns {Promise<void>}
 */
export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
