/**
 * Scraper registry - maps website names to their scraper modules
 */

import * as journal from './journal.js';
import * as mitchellh from './mitchellh.js';
import * as macwright from './macwright.js';
import * as overreacted from './overreacted.js';
import * as thinkingeek from './thinkingeek.js';
import * as greydanus from './greydanus.js';
import * as lisper from './lisper.js';
import * as paulgraham from './paulgraham.js';
import * as marijnhaverbeke from './marijnhaverbeke.js';
import * as emgoto from './emgoto.js';
import * as hawksley from './hawksley.js';

export const scrapers = {
  journal,
  mitchellh,
  macwright,
  overreacted,
  thinkingeek,
  greydanus,
  lisper,
  paulgraham,
  marijnhaverbeke,
  emgoto,
  hawksley,
};

/**
 * Get scraper module for a website
 * @param {string} name - Website name
 * @returns {object|null}
 */
export function getScraper(name) {
  return scrapers[name] || null;
}
