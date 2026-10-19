import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  parseDate,
  formatDateISO,
  resolveUrl,
  normalizeWhitespace,
} from '../src/utils.js';

describe('parseDate', () => {
  it('parses ISO format (YYYY-MM-DD)', () => {
    const date = parseDate('2025-12-01');
    assert.strictEqual(date.getFullYear(), 2025);
    assert.strictEqual(date.getMonth(), 11);
    assert.strictEqual(date.getDate(), 1);
  });

  it('parses full month format (December 1, 2025)', () => {
    const date = parseDate('December 1, 2025');
    assert.strictEqual(date.getFullYear(), 2025);
    assert.strictEqual(date.getMonth(), 11);
    assert.strictEqual(date.getDate(), 1);
  });

  it('parses abbreviated month format (Dec 1, 2025)', () => {
    const date = parseDate('Dec 1, 2025');
    assert.strictEqual(date.getFullYear(), 2025);
    assert.strictEqual(date.getMonth(), 11);
    assert.strictEqual(date.getDate(), 1);
  });

  it('parses day-of-week prefix format (Tuesday, September 30, 2025)', () => {
    const date = parseDate('Tuesday, September 30, 2025');
    assert.strictEqual(date.getFullYear(), 2025);
    assert.strictEqual(date.getMonth(), 8);
    assert.strictEqual(date.getDate(), 30);
  });

  it('returns null for invalid date', () => {
    assert.strictEqual(parseDate('not a date'), null);
    assert.strictEqual(parseDate(''), null);
    assert.strictEqual(parseDate(null), null);
  });
});

describe('formatDateISO', () => {
  it('formats date to YYYY-MM-DD', () => {
    const date = new Date(2025, 11, 1);
    assert.strictEqual(formatDateISO(date), '2025-12-01');
  });

  it('pads single-digit months and days', () => {
    const date = new Date(2025, 0, 5);
    assert.strictEqual(formatDateISO(date), '2025-01-05');
  });

  it('returns null for null input', () => {
    assert.strictEqual(formatDateISO(null), null);
  });
});

describe('resolveUrl', () => {
  it('resolves relative URL against base', () => {
    const result = resolveUrl('/blog/post', 'https://example.com/archive/');
    assert.strictEqual(result, 'https://example.com/blog/post');
  });

  it('keeps absolute URLs unchanged', () => {
    const result = resolveUrl('https://other.com/page', 'https://example.com/');
    assert.strictEqual(result, 'https://other.com/page');
  });

  it('returns empty string for empty href', () => {
    assert.strictEqual(resolveUrl('', 'https://example.com/'), '');
  });
});

describe('normalizeWhitespace', () => {
  it('collapses multiple spaces', () => {
    assert.strictEqual(normalizeWhitespace('hello   world'), 'hello world');
  });

  it('trims leading and trailing whitespace', () => {
    assert.strictEqual(normalizeWhitespace('  hello  '), 'hello');
  });

  it('handles newlines and tabs', () => {
    assert.strictEqual(normalizeWhitespace('hello\n\tworld'), 'hello world');
  });

  it('returns empty string for null/undefined', () => {
    assert.strictEqual(normalizeWhitespace(null), '');
    assert.strictEqual(normalizeWhitespace(undefined), '');
  });
});
