import { describe, it } from 'node:test';
import assert from 'node:assert';
import { generateArticleFilename } from '../src/fixtures.js';

describe('generateArticleFilename', () => {
  it('generates filename from URL path', () => {
    const filename = generateArticleFilename('https://example.com/blog/my-post');
    assert.strictEqual(filename, 'blog-my-post.html');
  });

  it('removes .html extension before adding it back', () => {
    const filename = generateArticleFilename('https://example.com/post.html');
    assert.strictEqual(filename, 'post.html');
  });

  it('prefixes with date if provided', () => {
    const filename = generateArticleFilename('https://example.com/post', '2025-12-01');
    assert.strictEqual(filename, '2025-12-01-post.html');
  });

  it('does not duplicate date prefix', () => {
    const filename = generateArticleFilename('https://example.com/2025-12-01/post', '2025-12-01');
    assert.strictEqual(filename, '2025-12-01-post.html');
  });

  it('sanitizes special characters', () => {
    const filename = generateArticleFilename('https://example.com/post?foo=bar&baz=qux');
    assert.ok(!filename.includes('?'));
    assert.ok(!filename.includes('&'));
    assert.ok(!filename.includes('='));
  });

  it('handles trailing slashes', () => {
    const filename = generateArticleFilename('https://example.com/blog/post/');
    assert.strictEqual(filename, 'blog-post.html');
  });
});
