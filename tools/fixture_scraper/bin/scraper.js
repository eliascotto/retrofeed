#!/usr/bin/env node

/**
 * CLI for the Retrofeed scraper
 *
 * Usage:
 *   node bin/scraper.js list                    # List available websites
 *   node bin/scraper.js archive <website>       # Scrape archive and save fixtures
 *   node bin/scraper.js archive-all             # Scrape archives for all websites
 *   node bin/scraper.js articles <website>      # Scrape all articles for a website
 *   node bin/scraper.js article <website> <url> # Scrape a single article
 */

import { program } from 'commander';
import { scrapeArchive, scrapeArticle, scrapeAllArticles, scrapeFavicon } from '../src/scraper.js';
import { listWebsites, getWebsiteConfig } from '../src/config.js';
import {
  saveArchiveFixtures,
  saveArticleFixture,
  loadArchiveFixtures,
  listArticleFixtures,
  generateArticleFilename,
  articleFixtureExists,
  saveFavicon,
} from '../src/fixtures.js';
import { getConfig, getRequestDelay } from '../src/env.js';

program
  .name('scraper')
  .description('Retrofeed blog archive and article scraper')
  .version('1.0.0');

// List command
program
  .command('list')
  .description('List all available websites')
  .action(() => {
    const websites = listWebsites();
    console.log('\nAvailable websites:\n');
    websites.forEach(({ index, name, url, description }) => {
      console.log(`  ${index}: ${name}`);
      console.log(`     ${description}`);
      console.log(`     ${url}\n`);
    });
  });

// Archive command
program
  .command('archive <website>')
  .description('Scrape archive page and save fixtures')
  .option('--dry-run', 'Print results without saving')
  .option('--favicon', 'Only scrape favicon (skip archive scraping)')
  .action(async (website, options) => {
    const config = getWebsiteConfig(website);
    if (!config) {
      console.error(`Unknown website: ${website}`);
      console.error('Use "scraper list" to see available websites');
      process.exit(1);
    }

    // If --favicon flag is set, only scrape favicon
    if (options.favicon) {
      console.log(`Scraping favicon for ${config.name} (${config.url})...`);

      try {
        const { faviconUrl, faviconData } = await scrapeFavicon(config.name);

        if (!faviconData) {
          console.log('No favicon found');
          return;
        }

        if (options.dryRun) {
          console.log(`\nFound favicon: ${faviconUrl}`);
          console.log(`Size: ${faviconData.length} bytes`);
        } else {
          const faviconPath = await saveFavicon(config.name, faviconData, faviconUrl);
          console.log(`\nSaved favicon: ${faviconPath}`);
        }
      } catch (err) {
        console.error(`Error: ${err.message}`);
        process.exit(1);
      }
      return;
    }

    // Normal archive scraping (with favicon by default)
    console.log(`Scraping archive for ${config.name} (${config.url})...`);

    try {
      const { articles, html } = await scrapeArchive(config.name);

      console.log(`Found ${articles.length} articles`);

      if (options.dryRun) {
        console.log('\nArticles (first 10):');
        articles.slice(0, 10).forEach((art) => {
          console.log(`  ${art.order}. ${art.title}`);
          console.log(`     Date: ${art.date || 'N/A'}`);
          console.log(`     Link: ${art.link}`);
          if (art.tags.length) {
            console.log(`     Tags: ${art.tags.join(', ')}`);
          }
          console.log('');
        });
      } else {
        const { htmlPath, jsonPath } = await saveArchiveFixtures(config.name, articles, html);
        console.log(`\nSaved fixtures:`);
        console.log(`  HTML: ${htmlPath}`);
        console.log(`  JSON: ${jsonPath}`);

        // Scrape and save favicon by default
        try {
          const { faviconUrl, faviconData } = await scrapeFavicon(config.name, { html });
          if (faviconData) {
            const faviconPath = await saveFavicon(config.name, faviconData, faviconUrl);
            console.log(`  Favicon: ${faviconPath}`);
          }
        } catch (err) {
          console.warn(`  Warning: Failed to scrape favicon: ${err.message}`);
        }
      }
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// Archive-all command
program
  .command('archive-all')
  .description('Scrape archive pages for all websites and save fixtures')
  .option('--dry-run', 'Print results without saving')
  .option('--favicon', 'Only scrape favicons (skip archive scraping)')
  .action(async (options) => {
    const websites = listWebsites();

    console.log(`\nScraping archives for ${websites.length} websites...\n`);

    let successCount = 0;
    let failCount = 0;
    const delay = getRequestDelay();

    for (let i = 0; i < websites.length; i++) {
      const { name, url } = websites[i];

      process.stdout.write(`[${i + 1}/${websites.length}] ${name}...`);

      try {
        // If --favicon flag is set, only scrape favicon
        if (options.favicon) {
          const { faviconUrl, faviconData } = await scrapeFavicon(name);

          if (!faviconData) {
            process.stdout.write(` no favicon found\n`);
            failCount++;
            continue;
          }

          if (options.dryRun) {
            process.stdout.write(` found (${faviconData.length} bytes)\n`);
            successCount++;
          } else {
            const faviconPath = await saveFavicon(name, faviconData, faviconUrl);
            process.stdout.write(` saved\n`);
            successCount++;
          }
        } else {
          // Normal archive scraping (with favicon by default)
          const { articles, html } = await scrapeArchive(name);

          if (options.dryRun) {
            process.stdout.write(` ${articles.length} articles found\n`);
            successCount++;
          } else {
            const { htmlPath, jsonPath } = await saveArchiveFixtures(name, articles, html);
            process.stdout.write(` ${articles.length} articles saved`);

            // Scrape and save favicon by default
            try {
              const { faviconUrl, faviconData } = await scrapeFavicon(name, { html });
              if (faviconData) {
                await saveFavicon(name, faviconData, faviconUrl);
                process.stdout.write(` + favicon`);
              }
            } catch (err) {
              // Silently fail favicon scraping, don't fail the whole operation
            }

            process.stdout.write(`\n`);
            successCount++;
          }
        }
      } catch (err) {
        process.stdout.write(` FAILED: ${err.message}\n`);
        failCount++;
      }

      // Rate limit between websites
      if (i < websites.length - 1 && delay > 0) {
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }

    console.log(`\nDone. Success: ${successCount}, Failed: ${failCount}\n`);
  });

// Articles command
program
  .command('articles <website>')
  .description('Scrape all articles and save fixtures')
  .option('--limit <n>', 'Limit number of articles to scrape', parseInt)
  .option('--delay <ms>', 'Delay between requests in ms (default from env)', parseInt)
  .option('--dry-run', 'Print results without saving')
  .option('--skip-existing', 'Skip articles that already have fixtures')
  .action(async (website, options) => {
    const config = getWebsiteConfig(website);
    if (!config) {
      console.error(`Unknown website: ${website}`);
      process.exit(1);
    }

    console.log(`Scraping articles for ${config.name}...`);

    try {
      // First get archive to know what articles exist
      const { articles: archiveArticles } = await scrapeArchive(config.name);

      let articlesToScrape = archiveArticles;

      // Filter out existing if requested
      if (options.skipExisting) {
        const existingFixtures = await listArticleFixtures(config.name);
        const existingSet = new Set(existingFixtures);

        articlesToScrape = [];
        for (const article of archiveArticles) {
          const filename = generateArticleFilename(article.link, article.date);
          if (!existingSet.has(filename)) {
            articlesToScrape.push(article);
          }
        }

        console.log(`Skipping ${archiveArticles.length - articlesToScrape.length} existing fixtures`);
      }

      // Apply limit
      if (options.limit) {
        articlesToScrape = articlesToScrape.slice(0, options.limit);
      }

      console.log(`Will scrape ${articlesToScrape.length} articles\n`);

      if (options.dryRun) {
        articlesToScrape.forEach((art) => {
          console.log(`  ${art.title}`);
          console.log(`    ${art.link}\n`);
        });
        return;
      }

      // Scrape each article
      let saved = 0;
      let failed = 0;

      for (let i = 0; i < articlesToScrape.length; i++) {
        const article = articlesToScrape[i];

        process.stdout.write(`[${i + 1}/${articlesToScrape.length}] ${article.title.slice(0, 50)}...`);

        try {
          const result = await scrapeArticle(config.name, article.link);
          const path = await saveArticleFixture(
            config.name,
            article.link,
            result.html,
            article.date
          );
          process.stdout.write(` saved\n`);
          saved++;
        } catch (err) {
          process.stdout.write(` FAILED: ${err.message}\n`);
          failed++;
        }

        // Rate limit
        const delay = options.delay ?? getRequestDelay();
        if (i < articlesToScrape.length - 1 && delay > 0) {
          await new Promise((resolve) => setTimeout(resolve, delay));
        }
      }

      console.log(`\nDone. Saved: ${saved}, Failed: ${failed}`);
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// Single article command
program
  .command('article <website> <url>')
  .description('Scrape a single article')
  .option('--dry-run', 'Print results without saving')
  .action(async (website, url, options) => {
    const config = getWebsiteConfig(website);
    if (!config) {
      console.error(`Unknown website: ${website}`);
      process.exit(1);
    }

    console.log(`Scraping article: ${url}`);

    try {
      const { title, content, date, html } = await scrapeArticle(config.name, url);

      console.log(`\nTitle: ${title}`);
      console.log(`Date: ${date || 'N/A'}`);
      console.log(`Content length: ${content?.length || 0} chars`);

      if (!options.dryRun) {
        const path = await saveArticleFixture(config.name, url, html, date);
        console.log(`\nSaved to: ${path}`);
      }
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  });

// Status command - show which fixtures exist
program
  .command('status <website>')
  .description('Show fixture status for a website')
  .action(async (website) => {
    const config = getWebsiteConfig(website);
    if (!config) {
      console.error(`Unknown website: ${website}`);
      process.exit(1);
    }

    console.log(`\nFixture status for ${config.name}:\n`);

    // Check archive
    const { html, articles } = await loadArchiveFixtures(config.name);
    console.log(`Archive HTML: ${html ? 'EXISTS' : 'MISSING'}`);
    console.log(`Archive JSON: ${articles ? `EXISTS (${articles.length} articles)` : 'MISSING'}`);

    // Check articles
    const articleFixtures = await listArticleFixtures(config.name);
    console.log(`Article fixtures: ${articleFixtures.length}`);

    if (articles && articleFixtures.length > 0) {
      // Calculate coverage
      const coverage = (articleFixtures.length / articles.length * 100).toFixed(1);
      console.log(`Coverage: ${coverage}%`);
    }

    console.log('');
  });

// All status command
program
  .command('status-all')
  .description('Show fixture status for all websites')
  .action(async () => {
    const websites = listWebsites();

    console.log('\nFixture status:\n');
    console.log('Website          | Archive | Articles | Coverage');
    console.log('-----------------+---------+----------+---------');

    for (const { name } of websites) {
      const { html, articles } = await loadArchiveFixtures(name);
      const articleFixtures = await listArticleFixtures(name);

      const archiveStatus = html && articles ? 'OK' : 'MISSING';
      const articleCount = articleFixtures.length;
      const coverage = articles && articles.length > 0
        ? `${(articleCount / articles.length * 100).toFixed(0)}%`
        : 'N/A';

      const namePadded = name.padEnd(16);
      const archivePadded = archiveStatus.padEnd(7);
      const articlesPadded = String(articleCount).padEnd(8);

      console.log(`${namePadded} | ${archivePadded} | ${articlesPadded} | ${coverage}`);
    }

    console.log('');
  });

// Config command - show current configuration
program
  .command('config')
  .description('Show current configuration')
  .action(() => {
    const config = getConfig();
    console.log('\nCurrent configuration:\n');
    console.log(`  Fixtures directory: ${config.fixturesDir}`);
    console.log(`  Request delay:      ${config.requestDelayMin}-${config.requestDelayMax}ms (random)`);
    console.log(`  Request timeout:    ${config.requestTimeout}ms`);
    console.log(`  User agent:         ${config.userAgent}`);
    console.log(`  Max concurrent:     ${config.maxConcurrent}`);
    console.log(`  Verbose:            ${config.verbose}`);
    console.log('\nSet these via .env file or environment variables.');
    console.log('See .env.example for available options.\n');
  });

program.parse();
