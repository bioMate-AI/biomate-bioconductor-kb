const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('../../../../frontend/node_modules/jsdom');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'contact.html'), 'utf8');
function setup(fetchImpl, query = '') {
  const dom = new JSDOM(html, { url: `https://biomate.ai/contact.html${query}`, runScripts: 'outside-only' });
  const w = dom.window;
  w.fetch = fetchImpl;
  const scripts = [...w.document.querySelectorAll('script:not([src])')];
  w.eval(scripts.find(s => s.textContent.includes('FORMSPREE_ENDPOINT')).textContent);
  const form = w.document.getElementById('cf-form');
  function submit() { form.dispatchEvent(new w.Event('submit', { bubbles: true, cancelable: true })); }
  function fill() {
    form.elements.namedItem('name').value = 'Synthetic QA';
    form.elements.namedItem('email').value = 'qa@example.invalid';
    form.elements.namedItem('message').value = 'Synthetic local test; never sent.';
  }
  return { dom, w, form, submit, fill, button: w.document.getElementById('cf-submit'), error: w.document.getElementById('cf-error'), success: w.document.getElementById('cf-success') };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
test('contact topic is decoded as plain text, not injected HTML', t => {
  const s = setup(() => { throw Error('Unexpected network'); }, '?topic=%3Cimg%20src%3Dx%3E');
  t.after(() => s.dom.window.close());
  assert.equal(s.form.elements.namedItem('topic').value, '<img src=x>');
  assert.equal(s.form.elements.namedItem('topic').querySelector('img'), null);
});
test('empty and malformed required fields never dispatch a request', t => {
  let calls = 0;
  const s = setup(() => { calls++; return Promise.resolve({ok:true}); });
  t.after(() => s.dom.window.close());
  s.submit(); s.fill(); s.form.elements.namedItem('email').value = 'invalid'; s.submit();
  assert.equal(calls, 0);
  assert.equal(s.button.disabled, false);
});
test('success requires an OK response; pending state does not claim success or double-submit', async t => {
  let calls = 0, resolveRequest;
  const s = setup((url, options) => {
    calls++;
    assert.equal(url, 'https://formspree.io/f/xlgvqqvz');
    assert.equal(options.method, 'POST');
    assert.equal(JSON.parse(options.body).email, 'qa@example.invalid');
    return new Promise(resolve => { resolveRequest = resolve; });
  });
  t.after(() => s.dom.window.close());
  s.fill(); s.submit(); s.submit();
  assert.equal(calls, 1);
  assert.equal(s.button.disabled, true);
  assert.notEqual(s.success.style.display, 'block');
  resolveRequest({ok:true}); await settle();
  assert.equal(s.form.style.display, 'none');
  assert.equal(s.success.style.display, 'block');
});
for (const failure of ['http', 'network', 'timeout']) {
  test(`contact ${failure} failure preserves input and allows a successful retry`, async t => {
    let calls = 0, timeoutCallback;
    const s = setup((_url, options) => {
      calls++;
      if (calls > 1) return Promise.resolve({ok:true});
      if (failure === 'http') return Promise.resolve({ok:false, status:429});
      if (failure === 'network') return Promise.reject(Error('network'));
      return new Promise((_resolve, reject) => options.signal.addEventListener('abort', () => reject(Error('aborted'))));
    });
    t.after(() => s.dom.window.close());
    s.w.setTimeout = callback => { timeoutCallback = callback; return 1; };
    s.fill(); s.submit();
    if (failure === 'timeout') { assert.equal(typeof timeoutCallback, 'function'); timeoutCallback(); }
    await settle();
    assert.equal(s.error.style.display, 'block');
    assert.equal(s.error.getAttribute('role'), 'alert');
    assert.match(s.error.textContent, /couldn't confirm/);
    assert.match(s.error.textContent, /duplicate/);
    assert.notEqual(s.success.style.display, 'block');
    assert.equal(s.button.disabled, false);
    assert.equal(s.form.elements.namedItem('message').value, 'Synthetic local test; never sent.');
    s.submit(); await settle();
    assert.equal(calls, 2);
    assert.equal(s.success.style.display, 'block');
    assert.equal(s.error.style.display, 'none');
  });
}
test('core visitor journeys retain connected discovery, evidence and contact destinations', () => {
  const load = file => new JSDOM(fs.readFileSync(path.join(root, file), 'utf8')).window.document;
  const has = (file, href) => assert.ok([...load(file).querySelectorAll('a[href]')].some(a => a.getAttribute('href') === href), `${file} → ${href}`);
  has('index.html', 'features.html'); has('features.html', 'pricing.html');
  has('pricing.html', 'https://dev-public.biomate.ai/register');
  has('index.html', 'drug-discovery.html'); has('drug-discovery.html', 'benchmarks-drug.html');
  has('drug-discovery.html', 'contact.html?topic=Drug%20discovery');
  has('index.html', 'research-engines.html'); has('research-engines.html', 'surveys.html');
  has('research-engines.html', 'survey-virtual-cell.html');
  has('research-engines.html', 'contact.html?topic=Cyclic%20peptide%20research');
  has('index.html', 'contact.html?topic=walkthrough');
});
