const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('../../../../frontend/node_modules/jsdom');
const root = path.resolve(__dirname, '..');
function setup() {
  const dom = new JSDOM('<div id="bm-nav"></div><main><button id="outside">Content</button></main><div id="bm-foot"></div>', { runScripts: 'outside-only', url: 'https://biomate.ai/index.html' });
  let breakpoint;
  dom.window.matchMedia = () => ({ addEventListener: (type, callback) => { breakpoint = callback; } });
  dom.window.eval(fs.readFileSync(path.join(root, 'shell.js'), 'utf8'));
  dom.window.renderShell({ active: 'drug', cta: false });
  const d = dom.window.document;
  return { dom, d, buttons: [...d.querySelectorAll('.bm-nav-trigger')], breakpoint: () => breakpoint() };
}
test('four disclosure panels retain category order and parallel groups', () => {
  const { d, buttons } = setup();
  assert.deepEqual(buttons.map(e => e.textContent.trim()), ['Company', 'Services', 'Research Engines', 'Evidence']);
  assert.ok(d.querySelector('#bm-panel-services').previousElementSibling.classList.contains('active'));
  assert.equal(d.querySelectorAll('nav[aria-label="Primary navigation"]').length, 1);
  for (const button of buttons) {
    assert.equal(button.tagName, 'BUTTON');
    assert.equal(button.getAttribute('aria-expanded'), 'false');
    const panel = d.getElementById(button.getAttribute('aria-controls'));
    assert.ok(panel.hasAttribute('inert'));
    assert.equal(panel.querySelectorAll('.bm-dropdown-group').length, 3);
  }
  const services = [...d.querySelectorAll('#bm-panel-services h2')].map(e => e.textContent);
  assert.deepEqual(services.slice(0, 2), ['Biomedical Research Platform', 'Drug Discovery']);
});
test('all previous destinations remain accessible and local targets exist', () => {
  const { d } = setup();
  const hrefs = [...d.querySelectorAll('.bm-dropdown a')].map(e => e.getAttribute('href'));
  for (const href of ['about.html','blog.html?cat=news','compare.html','contact.html','features.html','drug-discovery.html','services.html','tutorials.html','connectors.html','pricing.html','research-engines.html','research-engines.html#virtual-cell','research-engines.html#cyclic-peptides','benchmarks.html','publications.html','surveys.html','blog.html?cat=science']) assert.ok(hrefs.includes(href), href);
  for (const href of new Set(hrefs)) {
    const url = new URL(href, 'https://biomate.ai/');
    const filename = path.join(root, url.pathname);
    assert.ok(fs.existsSync(filename), href);
    if (url.hash) assert.ok(new JSDOM(fs.readFileSync(filename, 'utf8')).window.document.getElementById(url.hash.slice(1)), href);
  }
});
test('click toggles, switches and synchronizes visibility with ARIA', () => {
  const { d, buttons } = setup();
  buttons[0].click();
  assert.equal(buttons[0].getAttribute('aria-expanded'), 'true');
  assert.equal(d.querySelector('#bm-panel-company').hasAttribute('inert'), false);
  buttons[1].click();
  assert.equal(buttons[0].getAttribute('aria-expanded'), 'false');
  assert.ok(d.querySelector('#bm-panel-company').hasAttribute('inert'));
  assert.equal(d.querySelectorAll('.bm-dd-open').length, 1);
  buttons[1].click();
  assert.equal(d.querySelectorAll('.bm-dd-open').length, 0);
});
test('ArrowDown enters the panel; Escape closes it and restores trigger focus', () => {
  const { d, dom, buttons } = setup();
  buttons[0].focus();
  buttons[0].dispatchEvent(new dom.window.KeyboardEvent('keydown', { key:'ArrowDown', bubbles:true }));
  assert.equal(d.activeElement, d.querySelector('#bm-panel-company a'));
  d.activeElement.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key:'Escape', bubbles:true }));
  assert.equal(d.querySelectorAll('.bm-dd-open').length, 0);
  assert.equal(d.activeElement, buttons[0]);
});
test('focus leaving and clicking outside dismiss panels', () => {
  const { d, buttons } = setup();
  buttons[0].focus(); buttons[0].click();
  d.querySelector('#outside').focus();
  assert.equal(d.querySelectorAll('.bm-dd-open').length, 0);
  buttons[1].click(); d.querySelector('#outside').click();
  assert.equal(d.querySelectorAll('.bm-dd-open').length, 0);
});
test('mobile controls reset submenus, labels and breakpoint state', () => {
  const { d, buttons, breakpoint } = setup();
  const toggle = d.querySelector('#bmMobileToggle');
  toggle.click(); buttons[1].click();
  assert.equal(toggle.getAttribute('aria-label'), 'Close menu');
  assert.ok(d.querySelector('#bmNavLinks').classList.contains('bm-nav-open'));
  toggle.click();
  assert.equal(toggle.getAttribute('aria-label'), 'Open menu');
  assert.equal(d.querySelectorAll('.bm-dd-open').length, 0);
  toggle.click(); buttons[2].click(); breakpoint();
  assert.equal(toggle.getAttribute('aria-expanded'), 'false');
  assert.equal(d.querySelectorAll('.bm-dd-open').length, 0);
});
test('mobile focus transfer does not collapse content before the next trigger click', () => {
  const { d, dom, buttons } = setup();
  dom.window.innerWidth = 390;
  d.querySelector('#bmMobileToggle').click();
  buttons[1].focus(); buttons[1].click();
  buttons[3].focus();
  assert.equal(buttons[1].getAttribute('aria-expanded'), 'true');
  buttons[3].click();
  assert.equal(buttons[1].getAttribute('aria-expanded'), 'false');
  assert.equal(buttons[3].getAttribute('aria-expanded'), 'true');
  assert.equal(d.querySelector('#bmMobileToggle').getAttribute('aria-expanded'), 'true');
});
