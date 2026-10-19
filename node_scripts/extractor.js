import { Defuddle } from 'defuddle/node';
import { parseHTML } from 'linkedom';
import * as http from 'http';

// Configuration
const PORT = process.env.EXTRACTOR_PORT || 3880;
const MAX_BODY_SIZE = 50 * 1024 * 1024; // 50MB max request body

/**
 * Extractor Server
 *
 * A persistent HTTP server that extracts article content from HTML using Defuddle.
 * Designed to be long-running and handle requests from the Rails backend.
 *
 * Endpoints:
 *   POST /extract - Extract content from single or batch of URLs/HTML
 *   GET /health   - Health check endpoint
 *
 * Request formats:
 *   Single: { url: string, html?: string }
 *   Batch:  [{ url: string, html?: string }, ...]
 */

// ============================================================================
// Core Extraction Logic
// ============================================================================

/**
 * Extract article content from HTML using Defuddle
 *
 * @param {string} url - The URL of the page (used for resolving relative links)
 * @param {string|null} htmlInput - HTML string to parse (fetches from URL if null)
 * @returns {Promise<Object>} Extracted content with metadata, or error object
 */
async function extractContent(url, htmlInput = null) {
  try {
    let html;

    if (htmlInput) {
      // Validate HTML input
      if (typeof htmlInput !== 'string') {
        throw new Error(`Invalid HTML input: expected string, got ${typeof htmlInput}`);
      }
      if (htmlInput.length === 0) {
        throw new Error('HTML input is empty');
      }
      html = htmlInput;
    } else {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      html = await response.text();
    }

    // Ensure HTML is a valid string
    if (typeof html !== 'string' || html.length === 0) {
      throw new Error('Invalid HTML: empty or not a string');
    }

    // Parse HTML using linkedom (faster than jsdom, no native deps)
    const { document } = parseHTML(html);
    const pageUrl = url || 'about:blank';

    // Extract content using Defuddle with error handling
    let result;
    try {
      result = await Defuddle(document, pageUrl, {
        separateMarkdown: true,
      });
    } catch (defuddleError) {
      // Handle specific turndown/buffer errors
      if (defuddleError.message && defuddleError.message.includes('slice is not a function')) {
        log(`Turndown buffer error for ${url}, attempting without markdown conversion`);
        // Retry without markdown conversion as fallback
        result = await Defuddle(document, pageUrl, {
          separateMarkdown: false,
        });
        // Manually set contentMd to empty since conversion failed
        result.contentMarkdown = '';
      } else {
        throw defuddleError;
      }
    }

    return {
      url: result.url,
      title: result.title,
      description: result.description,
      author: result.author,
      published: result.published,
      wordCount: result.wordCount,
      site: result.site,
      contentHtml: result.content || '',
      contentMd: result.contentMarkdown || '',
    };
  } catch (error) {
    // Log full error details for debugging
    log(`Error extracting content for ${url}: ${error.message}`);
    if (error.stack) {
      log(`Stack trace: ${error.stack}`);
    }
    return { error: error.message };
  }
}

// ============================================================================
// HTTP Request Handlers
// ============================================================================

/**
 * Handle POST /extract requests
 * Supports both single item and batch processing
 */
async function handleExtract(req, res) {
  let body = '';
  let bodySize = 0;

  req.on('data', chunk => {
    bodySize += chunk.length;
    if (bodySize > MAX_BODY_SIZE) {
      res.writeHead(413, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Request body too large' }));
      req.destroy();
      return;
    }
    body += chunk.toString();
  });

  req.on('end', async () => {
    try {
      const data = JSON.parse(body);

      // Batch processing: array of items processed in parallel
      if (Array.isArray(data)) {
        const results = await Promise.all(
          data.map(item => extractContent(item.url, item.html || null))
        );
        sendJson(res, 200, results);
      } else {
        // Single item processing
        const result = await extractContent(data.url, data.html || null);
        sendJson(res, 200, result);
      }
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
  });
}

/**
 * Handle GET /health requests
 * Returns server status for health checks
 */
function handleHealth(req, res) {
  sendJson(res, 200, {
    status: 'ok',
    uptime: process.uptime(),
    memory: process.memoryUsage()
  });
}

/**
 * Main request router
 */
function handleRequest(req, res) {
  // Route requests based on method and path
  if (req.method === 'POST' && req.url === '/extract') {
    handleExtract(req, res);
  } else if (req.method === 'GET' && req.url === '/health') {
    handleHealth(req, res);
  } else {
    sendJson(res, 404, { error: 'Not Found' });
  }
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Send JSON response with proper headers
 */
function sendJson(res, statusCode, data) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

/**
 * Log message to stderr (avoids mixing with stdout in case of debugging)
 */
function log(message) {
  console.error(`[extractor] ${message}`);
}

// ============================================================================
// Server Lifecycle
// ============================================================================

const server = http.createServer(handleRequest);

server.listen(PORT, () => {
  log(`Server running on port ${PORT}`);
});

server.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    log(`ERROR: Port ${PORT} is already in use`);
    log(`Run 'lsof -i :${PORT}' to find the process, then 'kill <PID>' to stop it`);
    process.exit(1);
  } else {
    log(`Server error: ${error.message}`);
    if (error.stack) {
      log(`Stack trace: ${error.stack}`);
    }
    process.exit(1);
  }
});

// Graceful shutdown handlers
function shutdown(signal) {
  log(`Received ${signal}, shutting down...`);
  server.close(() => {
    log('Server closed');
    process.exit(0);
  });

  // Force exit after 10s if graceful shutdown fails
  setTimeout(() => {
    log('Forcing exit after timeout');
    process.exit(1);
  }, 10000);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
