/**
 * Website configurations for scrapers
 * Each website has its own scraper function for parsing archives and articles
 */

export const WEBSITES = {
  journal: {
    name: 'journal',
    url: 'https://journal.stuffwithstuff.com/archive/',
    description: 'Stuff with Stuff - Bob Nystrom',
  },
  mitchellh: {
    name: 'mitchellh',
    url: 'https://mitchellh.com/writing',
    description: 'Mitchell Hashimoto',
  },
  macwright: {
    name: 'macwright',
    url: 'https://macwright.com/writing',
    description: 'Tom MacWright',
  },
  overreacted: {
    name: 'overreacted',
    url: 'https://overreacted.io/',
    description: 'Dan Abramov - Overreacted',
  },
  thinkingeek: {
    name: 'thinkingeek',
    url: 'https://thinkingeek.com/archives/',
    description: 'Think In Geek',
  },
  greydanus: {
    name: 'greydanus',
    url: 'https://greydanus.github.io/',
    description: 'Sam Greydanus',
  },
  lisper: {
    name: 'lisper',
    url: 'https://lisper.in/',
    description: 'Lisper',
  },
  paulgraham: {
    name: 'paulgraham',
    url: 'https://www.paulgraham.com/articles.html',
    description: 'Paul Graham Essays',
  },
  marijnhaverbeke: {
    name: 'marijnhaverbeke',
    url: 'https://marijnhaverbeke.nl/blog/',
    description: 'Marijn Haverbeke',
  },
  emgoto: {
    name: 'emgoto',
    url: 'https://emgoto.com/posts/',
    description: 'Emma Goto',
  },
  hawksley: {
    name: 'hawksley',
    url: 'https://hawksley.org/',
    description: 'Joel Hawksley',
  },
};

/**
 * Get website config by name or index
 * @param {string|number} identifier - Website name or numeric index
 * @returns {object|null}
 */
export function getWebsiteConfig(identifier) {
  if (typeof identifier === 'number') {
    const keys = Object.keys(WEBSITES);
    if (identifier >= 0 && identifier < keys.length) {
      return WEBSITES[keys[identifier]];
    }
    return null;
  }
  return WEBSITES[identifier] || null;
}

/**
 * List all available websites
 * @returns {Array<{index: number, name: string, url: string, description: string}>}
 */
export function listWebsites() {
  return Object.keys(WEBSITES).map((key, index) => ({
    index,
    name: WEBSITES[key].name,
    url: WEBSITES[key].url,
    description: WEBSITES[key].description,
  }));
}
