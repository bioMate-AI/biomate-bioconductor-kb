const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('../../../../frontend/node_modules/jsdom');
const { prepare } = require('../../../../scripts/prepare_marketing_shell.cjs');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
test('all prepared public pages expose static navigation and a footer', () => {
  let checked = 0;
  for (const file of fs.readdirSync(root).filter(f => f.endsWith('.html'))) {
    const html = read(file);
    assert.equal(prepare(file, html), html, `stale shell: ${file}`);
    if (!html.includes('<!-- bm-static-nav:start -->')) continue;
    checked++;
    const d = new JSDOM(html).window.document; // No scripts execute.
    assert.equal(d.querySelectorAll('header.bm-nav').length, 1, file);
    assert.equal(d.querySelectorAll('footer.bm-footer').length, 1, file);
    const fallback = d.querySelector('noscript nav.bm-static-nav');
    assert.ok(fallback, `usable no-JavaScript navigation: ${file}`);
    for (const href of ['about.html', 'features.html', 'drug-discovery.html', 'research-engines.html', 'benchmarks.html', 'pricing.html', 'contact.html']) {
      assert.ok(fallback.querySelector(`a[href="${href}"]`), `${file}: ${href}`);
    }
  }
  assert.equal(checked, 97);
});
test('interactive enhancement replaces static markup without duplicate shells', () => {
  const dom = new JSDOM(read('index.html'), {runScripts:'outside-only', url:'https://biomate.ai/'});
  dom.window.matchMedia = () => ({addEventListener(){}});
  dom.window.eval(read('shell.js'));
  dom.window.renderShell({active:'home', cta:false});
  const d = dom.window.document;
  assert.equal(d.querySelectorAll('header.bm-nav').length, 1);
  assert.equal(d.querySelectorAll('footer.bm-footer').length, 1);
  assert.equal(d.querySelectorAll('.bm-nav-trigger').length, 4);
  assert.equal(d.querySelectorAll('.bm-static-nav').length, 0);
  const button = d.querySelector('.bm-nav-trigger');
  button.click();
  assert.equal(button.getAttribute('aria-expanded'), 'true');
});
test('preparation preserves content and CTA options and is idempotent', () => {
  const body = '<main><h1>Scientific content</h1><p data-value="a  b">Keep  spaces &amp; evidence.</p></main>';
  const source = '<div id="bm-nav"></div>' + body + '<div id="bm-foot"></div><script>renderShell({ active: \'drug\', cta: false });</script>';
  const output = prepare('example.html', source);
  assert.ok(output.includes(body));
  assert.equal(prepare('example.html', output), output);
  assert.ok(!output.includes('class="bm-cta-bar"'));
  assert.ok(prepare('example.html', source.replace('cta: false','cta: true')).includes('class="bm-cta-bar"'));
  assert.equal(prepare('blog-llm-comparison.html', source), source);
  assert.equal(prepare('login.html', source), source);
  assert.throws(() => prepare('example.html', source.replace('cta: false','unknown: true')), /Unsupported shell options/);
});
