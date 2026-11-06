const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('../../../../frontend/node_modules/jsdom');
const root = path.resolve(__dirname, '..');
const files = fs.readdirSync(root).filter(f => f.endsWith('.html'));
const docs = new Map(files.map(f => [f, new JSDOM(fs.readFileSync(path.join(root, f), 'utf8')).window.document]));
test('all local page links, static fragment targets and referenced assets resolve', () => {
  const failures = [];
  for (const [file, d] of docs) {
    for (const el of d.querySelectorAll('a[href], img[src], script[src], link[rel="stylesheet"]')) {
      const ref = el.getAttribute('href') || el.getAttribute('src');
      if (!ref || /^(https?:|mailto:|tel:|data:|javascript:)/.test(ref)) continue;
      const url = new URL(ref, `https://biomate.ai/${file}`);
      const target = decodeURIComponent(url.pathname.slice(1)) || 'index.html';
      if (!fs.existsSync(path.join(root, target))) failures.push(`${file}: missing ${ref}`);
      else if (url.hash && target.endsWith('.html') && !docs.get(target)?.getElementById(decodeURIComponent(url.hash.slice(1)))) failures.push(`${file}: missing fragment ${ref}`);
    }
  }
  assert.deepEqual(failures, []);
});
test('all pages have unique IDs and named static buttons', () => {
  for (const [file, d] of docs) {
    const ids = [...d.querySelectorAll('[id]')].map(e => e.id);
    assert.equal(new Set(ids).size, ids.length, `${file}: duplicate IDs`);
    for (const el of d.querySelectorAll('button, a.bm-btn')) {
      assert.ok(el.textContent.trim() || el.getAttribute('aria-label') || el.querySelector('img[alt]')?.alt, `${file}: unnamed control`);
    }
  }
});
test('published marketing pages request the refreshed shared CSS', () => {
  for (const [file, d] of docs) {
    // Authentication snapshots and separately managed comparison articles are not deployed here.
    if (/^(login|register|forgot-password|reset-password|blog-llm-comparison|blog-llm-comparison-supplement)\.html$/.test(file)) continue;
    assert.ok(d.querySelector('link[href="styles.css?v=20261010-ui2"]'), file);
  }
});
test('filled article buttons retain dedicated normal and hover color rules', () => {
  const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
  for (const scope of ['.bm-prose', '.article-body', '.ed-article']) {
    for (const state of ['', ':hover']) {
      const selector = `${scope} a.bm-btn-primary${state}`;
      const rule = css.split('}').find(r => r.split('{')[0].split(',').some(s => s.trim() === selector));
      assert.ok(rule, selector);
      assert.match(rule.split('{')[1], /color:\s*#fff\s*;/, selector);
    }
  }
});
test('wide capability tables retain accessible scroll containers', () => {
  for (const file of ['alphafold.html', 'benchmarks-biology.html', 'benchmarks-drug.html', 'molecular-docking.html', 'rna-seq.html', 'single-cell-rna-seq.html', 'connectors.html']) {
    for (const table of docs.get(file).querySelectorAll('table')) {
      const region = table.parentElement;
      assert.ok(region.classList.contains('bm-table-scroll'), file);
      assert.equal(region.getAttribute('tabindex'), '0', file);
      assert.equal(region.getAttribute('role'), 'region', file);
      assert.ok(region.getAttribute('aria-label'), file);
    }
  }
});
test('workflow pairs and four-card pricing do not force fixed desktop columns on mobile', () => {
  for (const file of ['admet-prediction.html', 'molecular-docking.html', 'variant-calling.html']) {
    for (const el of docs.get(file).querySelectorAll('div[style]')) {
      if (/grid-template-columns:\s*1fr 1fr/.test(el.getAttribute('style'))) assert.ok(el.classList.contains('bm-responsive-pair'), file);
    }
  }
  const grid = docs.get('pricing.html').querySelector('.bm-price-grid');
  assert.ok(grid.classList.contains('bm-price-grid-four'));
  assert.ok(!grid.getAttribute('style')?.includes('grid-template-columns'));
  assert.equal(grid.querySelectorAll('article').length, 4);
  const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
  assert.match(css, /@media\(max-width:760px\)\s*\{\s*\.bm-price-grid\.bm-price-grid-four\s*\{\s*grid-template-columns:1fr/);
});
