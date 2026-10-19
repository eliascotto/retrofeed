// Helper for DefuddleTest: reads HTML from stdin, runs defuddle, and writes
// { contentHtml, contentMd } as JSON to stdout. Errors go to stderr with a
// non-zero exit code so the Ruby side surfaces them.

import { Defuddle } from 'defuddle/node';
import { parseHTML } from 'linkedom';

let html = '';
for await (const chunk of process.stdin) html += chunk;

try {
  const { document } = parseHTML(html);
  const result = await Defuddle(document, 'http://test.local', { separateMarkdown: true });
  process.stdout.write(JSON.stringify({
    contentHtml: result.content || '',
    contentMd: result.contentMarkdown || ''
  }));
} catch (error) {
  process.stderr.write(`defuddle extraction failed: ${error.message}\n${error.stack || ''}`);
  process.exit(1);
}
