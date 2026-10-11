const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('../../../../frontend/node_modules/jsdom');
const root = path.resolve(__dirname, '..');
const read = f => fs.readFileSync(path.join(root, f), 'utf8');
test('ADMET score is scoped to workflow handling in visible and structured content', () => {
  for (const file of ['benchmarks.html', 'benchmarks-drug.html']) {
    const html = read(file);
    const d = new JSDOM(html).window.document;
    assert.ok(d.body.textContent.includes('60 ADMET workflow-handling prompts covering 20 compounds'));
    assert.ok(d.body.textContent.includes('Routing accuracy was 70%; parameter F1 was 95%'));
    assert.ok(!/58\/60|58 out of 60|2 failures from solubility|96\.3% (?:multi-property|ADMET prediction accuracy|ADMET accuracy)/.test(html));
    for (const meta of d.querySelectorAll('meta[name=description],meta[property="og:description"],meta[name="twitter:description"]')) {
      assert.match(meta.content, /workflow.handling/);
    }
    const schemas = [...d.querySelectorAll('script[type="application/ld+json"]')].map(s => JSON.parse(s.textContent));
    assert.ok(JSON.stringify(schemas).includes('not molecular prediction accuracy'));
  }
});
for (const file of ['index.html', 'drug-discovery.html', 'research-engines.html']) {
  test(`${file}: redesigned pages retain discoverability metadata`, () => {
    const d = new JSDOM(read(file)).window.document;
    const url = `https://biomate.ai/${file === 'index.html' ? '' : file}`;
    assert.equal(d.querySelector('link[rel=canonical]').href, url);
    assert.equal(d.querySelector('meta[property="og:url"]').content, url);
    for (const selector of ['meta[name=description]', 'meta[property="og:title"]', 'meta[property="og:image"]', 'meta[name="twitter:card"]', 'meta[name="twitter:image"]']) {
      assert.ok(d.querySelector(selector)?.content.trim(), selector);
    }
    const graphs = [...d.querySelectorAll('script[type="application/ld+json"]')].flatMap(s => {
      const value = JSON.parse(s.textContent); return value['@graph'] || [value];
    });
    assert.ok(graphs.some(g => g['@type'] === 'WebPage' && g.url === url));
    if (file === 'index.html') {
      for (const type of ['Organization', 'WebSite', 'SoftwareApplication']) assert.ok(graphs.some(g => g['@type'] === type));
      assert.ok(!graphs.some(g => g.potentialAction), 'do not invent a site search endpoint');
    }
    assert.ok(d.querySelector('script[src*="G-65JDDPEDQ5"]'));
    assert.ok(read('sitemap.xml').includes(`<loc>${url}</loc>`));
  });
}
test('benchmark FAQ remains readable without scripts and matches machine-readable answers', () => {
  const d = new JSDOM(read('benchmarks.html')).window.document;
  const rows = [...d.querySelectorAll('.bm-benchmark-faq > div')];
  assert.equal(rows.length, 7);
  assert.equal(d.querySelectorAll('.bm-benchmark-faq .bm-faq-item').length, 0, 'avoid shared accordion CSS collision');
  const schema = [...d.querySelectorAll('script[type="application/ld+json"]')].map(s => JSON.parse(s.textContent)).find(g => g['@type'] === 'FAQPage');
  assert.equal(schema.mainEntity.length, rows.length);
  rows.forEach((row, i) => {
    assert.equal(schema.mainEntity[i].name, row.querySelector('h3').textContent);
    assert.equal(schema.mainEntity[i].acceptedAnswer.text, row.querySelector('p').textContent);
  });
});
test('routing accuracy is reported as exact first-choice with partial-credit disclosure, not mislabeled as first-pick', () => {
  // 94.6% is a partial-credit aggregate (109 exact + 9 half-credit equivalents + 2 wrong over 120).
  // The strict exact first-choice figure is 90.8%. No surface may present 94.6% as the bare
  // "first-pick" routing number, and the two routing pages must show 90.8% with the aggregate disclosed.
  for (const file of ['benchmarks-routing.html', 'benchmarks.html', 'features.html', 'compare.html']) {
    const html = read(file);
    assert.ok(!/first-pick routing accuracy/i.test(html), `${file}: drop "first-pick routing accuracy" framing`);
    assert.ok(!/94\.6%\s*first[- ]?(pick|choice)/i.test(html), `${file}: 94.6% must not be labeled a first-pick/first-choice figure`);
  }
  for (const file of ['benchmarks-routing.html', 'benchmarks.html']) {
    const text = new JSDOM(read(file)).window.document.body.textContent;
    assert.ok(text.includes('90.8%'), `${file}: exact first-choice 90.8% must be shown`);
    assert.match(text, /equivalent pipelines|incl\. equivalents|including .*equivalent/i, `${file}: must disclose 94.6% counts equivalent pipelines (partial credit)`);
  }
});
test('the full workflow catalog count is not conflated with the validated subset', () => {
  // Catalog ~4,210 workflows; validated-by-real-execution subset is ~1,092. The catalog count
  // must not be described as "N validated workflows/pipelines".
  for (const file of ['about.html', 'services.html', 'features.html', 'benchmarks-routing.html', 'benchmarks.html', 'llms.txt', 'llms-full.txt']) {
    const txt = read(file);
    assert.ok(!/4,000\+ validated (bioinformatics )?(workflow|pipeline)/i.test(txt), `${file}: "4,000+" is a catalog count, not "validated"`);
    assert.ok(!/4,015 validated/i.test(txt), `${file}: "4,015" is a catalog count, not "validated"`);
  }
});
test('routing-family metrics use evidence-backed numbers and the correct metric type', () => {
  const html = read('benchmarks-routing.html');
  // License gating: every source says 98.1% (53/54); 98.2% was a transcription error the page
  // even contradicted with its own "1 of 54" prose.
  assert.ok(!/98\.2%/.test(html), 'license gating must be 98.1% (53/54), not 98.2%');
  assert.ok(/98\.1%/.test(html), 'license gating 98.1% must be shown');
  // Parameter extraction 0.848 is a mean per-case F1 (partial credit), not an all-or-nothing pass.
  assert.ok(!/test case passes if all required parameters/i.test(html), 'do not describe parameter extraction as all-or-nothing');
  assert.match(html, /mean per-case F1|mean F1/i, 'parameter extraction must be labeled as a mean F1');
});
test('canonical public HTML pages are represented once in the sitemap', () => {
  const xml = new JSDOM(read('sitemap.xml'), {contentType:'text/xml'}).window.document;
  const urls = [...xml.querySelectorAll('loc')].map(n => n.textContent);
  assert.equal(urls.length, new Set(urls).size);
  for (const file of fs.readdirSync(root).filter(f => f.endsWith('.html'))) {
    if (/^(login|register|forgot-password|reset-password)\.html$/.test(file)) continue;
    const d = new JSDOM(read(file)).window.document;
    if (d.querySelector('meta[name=robots][content*="noindex"]')) continue;
    const url = d.querySelector('link[rel=canonical]')?.href;
    // These two local snapshots are excluded from marketing deployment and
    // managed separately; their live metadata is checked by the HTTP audit.
    if (!/^blog-llm-comparison(?:-supplement)?\.html$/.test(file)) assert.ok(url, `${file}: missing canonical`);
    if (url) assert.ok(urls.includes(url), file);
  }
});
