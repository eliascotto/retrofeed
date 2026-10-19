#!/usr/bin/env node

import { createServer } from "node:http";
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, extname, resolve } from "node:path";
import { parseArgs } from "node:util";
import * as cheerio from "cheerio";

const FIXTURES_DIR = resolve(
  import.meta.dirname,
  "..",
  "..",
  "..",
  "test",
  "fixtures",
  "websites"
);

const ADMIN_HTML_PATH = resolve(import.meta.dirname, "admin.html");

const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
};

// Container elements we'll consider removing wholesale when they wrap an unpublished link.
const CONTAINER_TAGS = new Set(["li", "article", "tr", "dt", "dd", "p"]);

const fixtures = new Map();

function discoverFixtures() {
  if (!existsSync(FIXTURES_DIR)) {
    console.error(`Fixtures directory not found: ${FIXTURES_DIR}`);
    process.exit(1);
  }

  const entries = readdirSync(FIXTURES_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => entry.name)
    .sort();

  for (const name of entries) {
    const siteDir = join(FIXTURES_DIR, name);
    const archiveJsonPath = join(siteDir, "archive.json");
    const archiveHtmlPath = join(siteDir, "archive.html");

    if (!existsSync(archiveJsonPath)) {
      console.warn(`[skip] ${name}: no archive.json`);
      continue
    }
    if (!existsSync(archiveHtmlPath)) {
      console.warn(`[skip] ${name}: no archive.html`);
      continue
    }

    let articles
    try {
      articles = JSON.parse(readFileSync(archiveJsonPath, "utf-8"));
    } catch (err) {
      console.warn(`[skip] ${name}: invalid archive.json (${err.message})`);
      continue
    }

    articles = articles.slice().sort((a, b) => a.order - b.order);

    // Map URL pathname -> article entry. Pathname is normalized: no trailing
    // slash (unless root). We store the origin from the first article so we
    // can resolve relative hrefs in the archive HTML during filtering.
    const routeMap = new Map();
    let origin = null;
    for (const article of articles) {
      let url
      try {
        url = new URL(article.link);
      } catch {
        continue
      }
      origin ||= url.origin;
      const pathname = normalizePath(url.pathname);
      routeMap.set(pathname, article);
    }

    const articlesDir = join(siteDir, "articles");
    const hasArticleFiles = existsSync(articlesDir) && statSync(articlesDir).isDirectory();
    if (!hasArticleFiles) {
      console.warn(`[warn] ${name}: no articles/ directory; article files won't resolve`);
    }

    const defaultPublished = articles.length > 0 ? new Set([articles[0].order]) : new Set();

    fixtures.set(name, {
      name,
      siteDir,
      archiveHtmlPath,
      articles,
      routeMap,
      origin,
      published: defaultPublished,
      defaultPublished: new Set(defaultPublished),
      archiveCache: null,
      archiveCacheKey: null,
    });
  }
}

function normalizePath(pathname) {
  if (pathname.length > 1 && pathname.endsWith("/")) {
    return pathname.slice(0, -1);
  } else {
    return pathname;
  }
}

function publishedKey(fixture) {
  return Array.from(fixture.published).sort((a, b) => a - b).join(",");
}

function renderArchive(fixture) {
  const key = publishedKey(fixture);
  if (fixture.archiveCache && fixture.archiveCacheKey === key) {
    return fixture.archiveCache;
  }

  const raw = readFileSync(fixture.archiveHtmlPath, "utf-8");
  const unpublishedPaths = new Set();
  for (const [path, article] of fixture.routeMap) {
    if (!fixture.published.has(article.order)) {
      unpublishedPaths.add(path);
    }
  }

  if (unpublishedPaths.size === 0) {
    fixture.archiveCache = raw;
    fixture.archiveCacheKey = key;
    return raw;
  }

  const $ = cheerio.load(raw);
  const baseOrigin = fixture.origin || `https://${fixture.name}.example`;

  $("a[href]").each((_, el) => {
    const href = $(el).attr("href");
    if (!href) return;
    let resolved
    try {
      resolved = new URL(href, baseOrigin);
    } catch {
      return
    }
    const path = normalizePath(resolved.pathname);
    if (!unpublishedPaths.has(path)) return;

    // Decide whether to remove a container ancestor or just the <a>.
    let target = el;
    let parent = el.parent;
    while (parent && parent.type === "tag") {
      if (CONTAINER_TAGS.has(parent.name)) {
        // Only remove the container if it doesn't also contain a published article link.
        const otherPublished = $(parent)
          .find("a[href]")
          .toArray()
          .some((other) => {
            if (other === el) return false;
            const otherHref = $(other).attr("href");
            if (!otherHref) return false;
            try {
              const otherPath = normalizePath(new URL(otherHref, baseOrigin).pathname);
              return fixture.routeMap.has(otherPath) && !unpublishedPaths.has(otherPath);
            } catch {
              return false
            }
          });
        if (!otherPublished) {
          target = parent;
        }
        break
      }
      parent = parent.parent;
    }

    $(target).remove();
  });

  const out = $.html();
  fixture.archiveCache = out;
  fixture.archiveCacheKey = key;
  return out;
}

function invalidateCache(fixture) {
  fixture.archiveCache = null;
  fixture.archiveCacheKey = null;
}

function serveFile(filePath, res) {
  if (!existsSync(filePath)) {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not Found");
    return;
  }

  const ext = extname(filePath);
  const contentType = CONTENT_TYPES[ext] || "application/octet-stream";
  const body = readFileSync(filePath);
  res.writeHead(200, { "Content-Type": contentType });
  res.end(body);
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(body);
}

function sendText(res, status, text) {
  res.writeHead(status, { "Content-Type": "text/plain; charset=utf-8" });
  res.end(text);
}

function parseHost(hostHeader) {
  if (!hostHeader) {
    return { subdomain: null, hostname: null };
  }
  const hostname = hostHeader.split(":")[0].toLowerCase();
  const parts = hostname.split(".");
  if (parts.length >= 2 && parts[parts.length - 1] === "localhost") {
    return { subdomain: parts.slice(0, -1).join("."), hostname };
  } else {
    return { subdomain: null, hostname };
  }
}

function handleFixtureRequest(fixture, req, res) {
  const pathname = new URL(req.url, "http://placeholder").pathname;

  if (req.method !== "GET" && req.method !== "HEAD") {
    sendText(res, 405, "Method Not Allowed");
    return;
  }

  // Serve the filtered archive for both `/` and `/archive.html`. Retrofeed's
  // archive auto-detection often records the latter, and serving the raw file
  // would leak unpublished articles into the scraper.
  if (pathname === "/" || pathname === "/archive.html" || pathname === "/archive") {
    const html = renderArchive(fixture);
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(html);
    console.log(`[${fixture.name}] GET ${pathname}  ->  archive (filtered, ${fixture.published.size}/${fixture.articles.length})`);
    return;
  }

  if (pathname.startsWith("/favicon")) {
    const faviconPng = join(fixture.siteDir, "favicon.png");
    const faviconJpg = join(fixture.siteDir, "favicon.jpg");
    const faviconIco = join(fixture.siteDir, "favicon.ico");
    const faviconPath = existsSync(faviconPng) ? faviconPng
      : existsSync(faviconJpg) ? faviconJpg
      : faviconIco;
    serveFile(faviconPath, res);
    return;
  }

  const normalized = normalizePath(pathname);
  const article = fixture.routeMap.get(normalized);
  if (article) {
    if (fixture.published.has(article.order)) {
      const filePath = join(fixture.siteDir, article.file);
      console.log(`[${fixture.name}] GET ${pathname}  ->  ${article.file}`);
      serveFile(filePath, res);
    } else {
      console.log(`[${fixture.name}] GET ${pathname}  ->  404 (unpublished, order=${article.order})`);
      sendText(res, 404, "Not Found");
    }
    return;
  }

  // Fall back to static asset lookup inside the fixture directory. Keep this
  // confined to the fixture dir to avoid path traversal.
  const staticPath = join(fixture.siteDir, pathname);
  if (staticPath.startsWith(fixture.siteDir) && existsSync(staticPath) && statSync(staticPath).isFile()) {
    console.log(`[${fixture.name}] GET ${pathname}  ->  static`);
    serveFile(staticPath, res);
    return;
  }

  console.log(`[${fixture.name}] GET ${pathname}  ->  404`);
  sendText(res, 404, "Not Found");
}

function fixtureSummary(fixture) {
  return {
    name: fixture.name,
    total: fixture.articles.length,
    publishedCount: fixture.published.size,
  };
}

function fixtureDetail(fixture) {
  const articles = fixture.articles.map((article) => {
    let path = null;
    try {
      path = normalizePath(new URL(article.link).pathname);
    } catch {}
    return {
      order: article.order,
      title: article.title,
      date: article.date,
      link: article.link,
      path,
      file: article.file,
      published: fixture.published.has(article.order),
    };
  });
  return { name: fixture.name, articles };
}

function handleAdminRequest(req, res) {
  const url = new URL(req.url, "http://placeholder");
  const pathname = url.pathname;
  const method = req.method;

  if (method === "GET" && pathname === "/") {
    serveFile(ADMIN_HTML_PATH, res);
    return;
  }

  if (method === "GET" && pathname === "/api/fixtures") {
    const list = Array.from(fixtures.values()).map(fixtureSummary);
    sendJson(res, 200, list);
    return;
  }

  const detailMatch = pathname.match(/^\/api\/fixtures\/([^/]+)$/);
  if (method === "GET" && detailMatch) {
    const fixture = fixtures.get(detailMatch[1]);
    if (!fixture) {
      sendJson(res, 404, { error: "fixture not found" });
      return;
    }
    sendJson(res, 200, fixtureDetail(fixture));
    return;
  }

  const publishMatch = pathname.match(/^\/api\/fixtures\/([^/]+)\/articles\/(\d+)\/publish$/);
  if (publishMatch && (method === "POST" || method === "DELETE")) {
    const fixture = fixtures.get(publishMatch[1]);
    if (!fixture) {
      sendJson(res, 404, { error: "fixture not found" });
      return;
    }
    const order = parseInt(publishMatch[2], 10);
    const known = fixture.articles.some((a) => a.order === order);
    if (!known) {
      sendJson(res, 404, { error: "article not found" });
      return;
    }
    if (method === "POST") {
      fixture.published.add(order);
    } else {
      fixture.published.delete(order);
    }
    invalidateCache(fixture);
    console.log(`[${fixture.name}] ${method === "POST" ? "publish" : "unpublish"} order=${order} (now ${fixture.published.size}/${fixture.articles.length})`);
    res.writeHead(204);
    res.end();
    return;
  }

  const bulkMatch = pathname.match(/^\/api\/fixtures\/([^/]+)\/(reset|publish-all|unpublish-all)$/);
  if (bulkMatch && method === "POST") {
    const fixture = fixtures.get(bulkMatch[1]);
    if (!fixture) {
      sendJson(res, 404, { error: "fixture not found" });
      return;
    }
    if (bulkMatch[2] === "reset") {
      fixture.published = new Set(fixture.defaultPublished);
    } else if (bulkMatch[2] === "publish-all") {
      fixture.published = new Set(fixture.articles.map((a) => a.order));
    } else {
      fixture.published = new Set();
    }
    invalidateCache(fixture);
    console.log(`[${fixture.name}] ${bulkMatch[2]} (now ${fixture.published.size}/${fixture.articles.length})`);
    res.writeHead(204);
    res.end();
    return;
  }

  sendText(res, 404, "Not Found");
}

function handleRequest(req, res) {
  const { subdomain } = parseHost(req.headers.host);
  if (subdomain && fixtures.has(subdomain)) {
    handleFixtureRequest(fixtures.get(subdomain), req, res);
  } else {
    handleAdminRequest(req, res);
  }
}

function main() {
  const { values } = parseArgs({
    options: {
      port: { type: "string", short: "p", default: "8765" },
      help: { type: "boolean", short: "h", default: false },
    },
    allowPositionals: true,
  });

  if (values.help) {
    console.log("Usage: fixture-server [--port <port>]");
    console.log("");
    console.log("Serves every fixture under test/fixtures/websites/ as its own");
    console.log("<name>.localhost subdomain on a single port. The apex host");
    console.log("(localhost) exposes an admin UI at / for publishing articles.");
    console.log("");
    console.log("Options:");
    console.log("  -p, --port    Port to listen on (default: 8765)");
    console.log("  -h, --help    Show this help message");
    process.exit(0);
  }

  discoverFixtures();

  if (fixtures.size === 0) {
    console.error("No usable fixtures found.");
    process.exit(1);
  }

  const port = parseInt(values.port, 10);
  const server = createServer(handleRequest);

  server.listen(port, () => {
    console.log(`Mounted ${fixtures.size} fixtures at http://localhost:${port}/`);
    for (const fixture of fixtures.values()) {
      console.log(`  http://${fixture.name}.localhost:${port}/  (${fixture.articles.length} articles, ${fixture.published.size} published)`);
    }
  });
}

main();
