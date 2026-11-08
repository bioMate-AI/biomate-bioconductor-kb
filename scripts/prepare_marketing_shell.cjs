#!/usr/bin/env node
// Emit an apply_patch patch, or check freshness. Never writes source files.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../reference/claude_design/webpage_design_v2');
const { navHTML, ctaHTML, footerHTML } = require(path.join(root, 'shell.js'));
const preserved = new Set(['blog-llm-comparison.html', 'blog-llm-comparison-supplement.html', 'login.html', 'register.html', 'forgot-password.html', 'reset-password.html']);
const compact = html => html.replace(/\s+/g, ' ').trim();
function prepare(file, source) {
  if (preserved.has(file)) return source;
  const call = source.match(/renderShell\(\s*\{([^}]*)\}\s*\)/);
  if (!call) return source;
  const options = call[1];
  if (!/^\s*(?:(?:active\s*:\s*'[^']*'|lang\s*:\s*'[^']*'|cta\s*:\s*(?:true|false))\s*,?\s*)*$/.test(options)) throw new Error(`Unsupported shell options in ${file}`);
  const active = options.match(/active\s*:\s*'([^']*)'/)?.[1] || '';
  const lang = options.match(/lang\s*:\s*'([^']*)'/)?.[1] || '';
  const cta = !/cta\s*:\s*false/.test(options);
  // No-JavaScript fallback. The dropdown destinations (about/features/…) stay
  // shared EN pages, so only labels localize; the brand link follows the lang.
  const fallback = lang === 'zh'
    ? '<noscript><style>.bm-nav{display:none}</style><nav class="bm-static-nav" aria-label="无 JavaScript 时的主导航"><a href="index-zh.html">BioMate AI</a><a href="about.html">公司</a><a href="features.html">研究平台</a><a href="drug-discovery.html">药物发现</a><a href="research-engines.html">研究引擎</a><a href="benchmarks.html">证据</a><a href="pricing.html">价格</a><a href="contact.html">联系我们</a></nav></noscript>'
    : '<noscript><style>.bm-nav{display:none}</style><nav class="bm-static-nav" aria-label="Primary navigation without JavaScript"><a href="index.html">BioMate AI</a><a href="about.html">Company</a><a href="features.html">Research Platform</a><a href="drug-discovery.html">Drug Discovery</a><a href="research-engines.html">Research Engines</a><a href="benchmarks.html">Evidence</a><a href="pricing.html">Pricing</a><a href="contact.html">Contact</a></nav></noscript>';
  let next = source;
  for (const [part, html] of [['nav', compact(navHTML(active, lang)) + fallback], ['foot', compact((cta ? ctaHTML(lang) : '') + footerHTML(lang))]]) {
    const start = `<!-- bm-static-${part}:start -->`, end = `<!-- bm-static-${part}:end -->`;
    const block = `${start}\n<div id="bm-${part}">${html}</div>\n${end}`;
    const from = next.indexOf(start), to = next.indexOf(end);
    if (from >= 0 && to >= from) next = next.slice(0, from) + block + next.slice(to + end.length);
    else {
      const mount = `<div id="bm-${part}"></div>`;
      if (!next.includes(mount)) throw new Error(`Missing ${part} mount in ${file}`);
      next = next.replace(mount, block);
    }
  }
  return next;
}
function patch(file, old, next) {
  const a = old.split('\n'), b = next.split('\n');
  let i = 0, j = 0, text = '';
  while (i < a.length || j < b.length) {
    if (a[i] === b[j]) { i++; j++; continue; }
    const i0 = i, j0 = j;
    while (i < a.length && !b.slice(j).includes(a[i])) i++;
    if (i === a.length) j = b.length;
    else while (j < b.length && b[j] !== a[i]) j++;
    text += '@@\n' + (i0 > 0 ? ' ' + a[i0 - 1] + '\n' : '') + a.slice(i0, i).map(x => '-' + x + '\n').join('') + b.slice(j0, j).map(x => '+' + x + '\n').join('') + (i < a.length ? ' ' + a[i] + '\n' : '');
  }
  return `*** Update File: ${path.join(root, file)}\n${text}`;
}
if (require.main === module) {
  const changed = [];
  const selected = process.argv.find(x => x.startsWith('--file='))?.slice(7);
  for (const file of fs.readdirSync(root).filter(f => f.endsWith('.html') && (!selected || selected === f))) {
    const old = fs.readFileSync(path.join(root, file), 'utf8'), next = prepare(file, old);
    if (old !== next) changed.push({file, old, next});
  }
  if (process.argv.includes('--patch')) process.stdout.write('*** Begin Patch\n' + changed.map(x => patch(x.file, x.old, x.next)).join('') + '*** End Patch\n');
  else {
    console.log(changed.length ? `Stale marketing shells (${changed.length}): ${changed.map(x => x.file).join(', ')}` : 'Marketing shells are current.');
    process.exitCode = changed.length ? 1 : 0;
  }
}
module.exports = { prepare };
