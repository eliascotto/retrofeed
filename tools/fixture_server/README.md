# fixture-server

Serves every fixture under `test/fixtures/websites/` as its own `*.localhost`
subdomain on a single port. Used to point Retrofeed at scraped fixtures
instead of live blogs while developing or testing.

## Installation

```bash
cd tools/fixture_server
npm install
```

## Usage

```bash
npm start                 # listens on 8765
node src/server.js -p 9000
```

On boot the server scans `test/fixtures/websites/`. Every directory that has
both `archive.json` and `archive.html` is mounted at
`http://<name>.localhost:8765/`. The apex host
`http://localhost:8765/` serves the admin UI.

`*.localhost` resolves to `127.0.0.1` on macOS and most Linux distros without
extra `/etc/hosts` entries (RFC 6761).

## How it works

### Per-fixture routes

Each subdomain serves one fixture directory:

| Request                                  | Response                                              |
| ---------------------------------------- | ----------------------------------------------------- |
| `GET /`                                  | `archive.html`, filtered to only published articles   |
| `GET /<article-path>`                    | Article HTML if published, otherwise `404`            |
| `GET /favicon.*`                         | `favicon.png` / `favicon.jpg` / `favicon.ico`         |
| `GET /<anything else>`                   | Static file from the fixture directory, else `404`    |

Article paths come from each entry's `link` field in `archive.json`. For
example `https://mitchellh.com/writing/abandoning-rubygems` is served at
`http://mitchellh.localhost:8765/writing/abandoning-rubygems`.

### Publish state

Every fixture starts with only its first article (lowest `order`) published.
Any request for an unpublished article returns `404`, and the archive HTML is
rewritten to remove its link — so Retrofeed sees the same surface area as if
the article had never been written. State is in-memory only; restarting the
server resets every fixture to the default.

Use the admin UI to flip articles on and off. The intended workflow:

1. Subscribe Retrofeed to `http://<name>.localhost:8765/`.
2. Refresh — only the first article appears.
3. Publish another article in the admin UI.
4. Refresh Retrofeed — it discovers the new article via the (now-updated)
   archive page.

### Archive filtering

The archive HTML is the real scraped markup from the original site, so its
structure differs per fixture. The filter uses `cheerio` to find every
`<a href>` whose resolved pathname matches an unpublished article. For each
match it walks up to the nearest list-like ancestor (`li`, `article`, `tr`,
`dt`, `dd`, `p`); if that ancestor contains no other published article links
it removes the whole ancestor, otherwise it removes just the `<a>`. The
filtered document is cached and only recomputed when the published set
changes.

## Admin UI

Open `http://localhost:8765/`. Left sidebar lists every mounted fixture with
a `published/total` badge. Selecting a fixture shows its article list with a
publish/unpublish toggle per row, plus `Reset`, `Publish all`, and
`Unpublish all` buttons.

## Admin API

The UI is built on top of a small JSON API. You can call it directly from
scripts or tests.

```
GET    /api/fixtures
GET    /api/fixtures/:name
POST   /api/fixtures/:name/articles/:order/publish
DELETE /api/fixtures/:name/articles/:order/publish
POST   /api/fixtures/:name/reset
POST   /api/fixtures/:name/publish-all
POST   /api/fixtures/:name/unpublish-all
```

Examples:

```bash
# List fixtures and counts
curl -s http://localhost:8765/api/fixtures

# Inspect one fixture's articles and published flags
curl -s http://localhost:8765/api/fixtures/mitchellh

# Publish / unpublish a single article (use the entry's `order` value)
curl -X POST   http://localhost:8765/api/fixtures/mitchellh/articles/3/publish
curl -X DELETE http://localhost:8765/api/fixtures/mitchellh/articles/3/publish

# Bulk operations
curl -X POST http://localhost:8765/api/fixtures/mitchellh/reset
curl -X POST http://localhost:8765/api/fixtures/mitchellh/publish-all
curl -X POST http://localhost:8765/api/fixtures/mitchellh/unpublish-all
```

## Fixtures without article files

Some directories (e.g. `emgoto`, `hawksley`) ship an `archive.json` but no
`articles/` folder. They still mount and show up in the admin UI, but every
article request will 404 — useful for testing archive-page parsing in
isolation. The server logs a `[warn]` line for these on startup.
