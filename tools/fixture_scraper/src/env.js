/**
 * Environment configuration
 * Loads settings from .env file and provides defaults
 */

import { config } from 'dotenv';
import { join, dirname, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, '..', '..', '..');
const scrapersRoot = join(__dirname, '..');

// Load .env file from lib/scrapers directory
config({ path: join(__dirname, '..', '.env') });

/**
 * Get fixtures directory path
 * @returns {string}
 */
export function getFixturesBasePath() {
  const envPath = process.env.FIXTURES_DIR;

  if (envPath) {
    if (isAbsolute(envPath)) {
      return envPath;
    }
    // Relative paths are resolved from project root
    return join(projectRoot, envPath);
  }

  // Default: fixtures-output relative to lib/scrapers
  return join(scrapersRoot, 'fixtures-output');
}

/**
 * Get request delay between fetches
 * 
 * This is the pause/delay (in milliseconds) between consecutive HTTP requests.
 * Used for rate limiting to avoid overwhelming servers by making requests too quickly.
 * Applied AFTER each request completes, BEFORE making the next request.
 * 
 * Returns a random delay between REQUEST_DELAY_MIN and REQUEST_DELAY_MAX (inclusive)
 * to make the scraper's request pattern less predictable and more human-like.
 * 
 * Example: If REQUEST_DELAY_MIN=500 and REQUEST_DELAY_MAX=3000, each delay will be
 * a random value between 500ms and 3000ms.
 * 
 * @returns {number} Random delay in milliseconds (default range: 500-3000)
 */
export function getRequestDelay() {
  const min = parseInt(process.env.REQUEST_DELAY_MIN, 10);
  const max = parseInt(process.env.REQUEST_DELAY_MAX, 10);
  
  const minDelay = isNaN(min) ? 500 : min;
  const maxDelay = isNaN(max) ? 3000 : max;
  
  // Ensure min <= max
  const actualMin = Math.min(minDelay, maxDelay);
  const actualMax = Math.max(minDelay, maxDelay);
  
  // Return random value between min and max (inclusive)
  return Math.floor(Math.random() * (actualMax - actualMin + 1)) + actualMin;
}

/**
 * Get request timeout
 * 
 * This is the maximum time (in milliseconds) to wait for a SINGLE HTTP request
 * to complete before aborting it. This is a timeout for individual requests,
 * not a delay between requests.
 * 
 * If a request takes longer than this timeout, it will be aborted and an error
 * will be thrown. This prevents the scraper from hanging indefinitely on slow
 * or unresponsive servers.
 * 
 * Example: If REQUEST_TIMEOUT=30000, each individual HTTP request will be
 * aborted if it takes longer than 30 seconds to complete.
 * 
 * @returns {number} Timeout in milliseconds (default: 30000)
 */
export function getRequestTimeout() {
  const timeout = parseInt(process.env.REQUEST_TIMEOUT, 10);
  return isNaN(timeout) ? 30000 : timeout;
}

/**
 * Get user agent string
 * @returns {string}
 */
export function getUserAgent() {
  return process.env.USER_AGENT || 'Mozilla/5.0 (compatible; Retrofeed/1.0; +https://retrofeed.com)';
}

/**
 * Get max concurrent requests
 * @returns {number}
 */
export function getMaxConcurrent() {
  const max = parseInt(process.env.MAX_CONCURRENT, 10);
  return isNaN(max) || max < 1 ? 1 : max;
}

/**
 * Check if verbose logging is enabled
 * @returns {boolean}
 */
export function isVerbose() {
  const verbose = process.env.VERBOSE;
  return verbose === 'true' || verbose === '1';
}

/**
 * Get request delay min value
 * @returns {number} Minimum delay in milliseconds (default: 500)
 */
export function getRequestDelayMin() {
  const min = parseInt(process.env.REQUEST_DELAY_MIN, 10);
  return isNaN(min) ? 500 : min;
}

/**
 * Get request delay max value
 * @returns {number} Maximum delay in milliseconds (default: 3000)
 */
export function getRequestDelayMax() {
  const max = parseInt(process.env.REQUEST_DELAY_MAX, 10);
  return isNaN(max) ? 3000 : max;
}

/**
 * Get all config values
 * @returns {object}
 */
export function getConfig() {
  return {
    fixturesDir: getFixturesBasePath(),
    requestDelayMin: getRequestDelayMin(),
    requestDelayMax: getRequestDelayMax(),
    requestTimeout: getRequestTimeout(),
    userAgent: getUserAgent(),
    maxConcurrent: getMaxConcurrent(),
    verbose: isVerbose(),
  };
}
