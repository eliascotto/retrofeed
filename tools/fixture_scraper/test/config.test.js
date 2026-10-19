import { describe, it } from 'node:test';
import assert from 'node:assert';
import { WEBSITES, getWebsiteConfig, listWebsites } from '../src/config.js';

describe('WEBSITES', () => {
  it('contains expected websites', () => {
    assert.ok(WEBSITES.journal);
    assert.ok(WEBSITES.mitchellh);
    assert.ok(WEBSITES.macwright);
    assert.ok(WEBSITES.overreacted);
    assert.ok(WEBSITES.thinkingeek);
    assert.ok(WEBSITES.greydanus);
    assert.ok(WEBSITES.lisper);
    assert.ok(WEBSITES.paulgraham);
    assert.ok(WEBSITES.marijnhaverbeke);
  });

  it('each website has required fields', () => {
    Object.values(WEBSITES).forEach((config) => {
      assert.ok(config.name, 'name is required');
      assert.ok(config.url, 'url is required');
      assert.ok(config.description, 'description is required');
    });
  });
});

describe('getWebsiteConfig', () => {
  it('returns config by name', () => {
    const config = getWebsiteConfig('journal');
    assert.strictEqual(config.name, 'journal');
    assert.ok(config.url.includes('stuffwithstuff'));
  });

  it('returns config by index', () => {
    const config = getWebsiteConfig(0);
    assert.strictEqual(config.name, 'journal');
  });

  it('returns null for unknown name', () => {
    assert.strictEqual(getWebsiteConfig('unknown'), null);
  });

  it('returns null for out-of-range index', () => {
    assert.strictEqual(getWebsiteConfig(999), null);
    assert.strictEqual(getWebsiteConfig(-1), null);
  });
});

describe('listWebsites', () => {
  it('returns array of website info', () => {
    const websites = listWebsites();
    assert.ok(Array.isArray(websites));
    assert.strictEqual(websites.length, Object.keys(WEBSITES).length);
  });

  it('includes index, name, url, and description', () => {
    const websites = listWebsites();
    websites.forEach((w, i) => {
      assert.strictEqual(w.index, i);
      assert.ok(w.name);
      assert.ok(w.url);
      assert.ok(w.description);
    });
  });
});
