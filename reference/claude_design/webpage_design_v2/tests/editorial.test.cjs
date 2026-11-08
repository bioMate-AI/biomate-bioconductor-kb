const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('../../../../frontend/node_modules/jsdom');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const topics = ['target-identification', 'patient-stratification', 'multi-omics', 'virtual-cell', 'protein-conformation'];

for (const topic of topics) {
  test(`${topic}: readable layers and preserved navigation targets`, () => {
    const d = new JSDOM(read(`survey-${topic}.html`)).window.document;
    assert.equal(d.querySelectorAll('main h1').length, 1);
    assert.equal(d.querySelectorAll('.ed-insights > div').length, 3);
    assert.equal(d.querySelectorAll('figure.ed-map ol > li').length, 3);
    assert.ok(d.querySelector('figure.ed-map figcaption').textContent.trim());
    assert.ok(d.querySelectorAll('.ed-chapter').length >= 5);
    const links = [...d.querySelectorAll('.ed-sidebar a[href^="#"]')];
    assert.ok(links.length >= 5);
    for (const link of links) assert.ok(d.getElementById(link.hash.slice(1)), link.hash);
    const ids = [...d.querySelectorAll('[id]')].map(e => e.id);
    assert.equal(ids.length, new Set(ids).size);
  });
  test(`${topic}: public prose and dated evidence`, () => {
    const d = new JSDOM(read(`survey-${topic}.html`)).window.document;
    const text = d.querySelector('main').textContent;
    assert.doesNotMatch(text, /docs\/[\w/.-]+\.md|this session|load-bearing|No DOIs fabricated|Companion showcase|Verified corrections carried through|Source-brief correction/i);
    assert.match(d.querySelector('.ed-meta').textContent, /Research snapshot:.*Presentation revised:/);
    assert.ok(d.querySelectorAll('article a[href^="https://"]').length > 0);
    for (const table of d.querySelectorAll('article table')) {
      assert.ok(table.parentElement.classList.contains('ed-table'));
      assert.equal(table.parentElement.getAttribute('tabindex'), '0');
    }
  });
}

test('library exposes all five research perspectives', () => {
  const d = new JSDOM(read('surveys.html')).window.document;
  for (const topic of topics) assert.ok(d.querySelector(`a[href="survey-${topic}.html"]`));
});

const blogs = [...topics.map(t => `blog-${t}.html`), 'blog-multi-omics-integration.html', 'blog-llm-comparison.html'];
for (const file of blogs) {
  test(`${file}: enhancement preserves content and builds working section links`, () => {
    const dom = new JSDOM(read(file), { runScripts: 'outside-only', url: `https://biomate.ai/${file}` });
    const d = dom.window.document;
    assert.ok(d.querySelector('link[href="editorial.css"]'));
    assert.ok(d.querySelector('script[src="editorial.js"]'));
    const article = d.querySelector('article.bm-prose, .article-body');
    const before = article.textContent;
    dom.window.eval(read('editorial.js'));
    assert.ok(article.classList.contains('ed-blog-article'));
    const links = [...article.querySelectorAll('.ed-blog-nav a')];
    assert.equal(links.length, article.querySelectorAll('h2').length);
    for (const link of links) assert.ok(d.getElementById(link.hash.slice(1)));
    const nav = article.querySelector('.ed-blog-nav');
    nav.remove();
    assert.equal(article.textContent, before);
    for (const table of article.querySelectorAll('table')) assert.ok(table.parentElement.classList.contains('ed-blog-table'));
  });
}
