/* Shared nav + footer + CTA rendering for BioMate v2.
   Call renderShell({ active: 'home'|'services'|'newsroom'|'pricing'|'about'|'contact' }) */

(function () {
  function svg(d, vb) {
    return `<svg viewBox="${vb || '0 0 24 24'}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  }

  var chevron = `<svg class="bm-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9"/></svg>`;

  // Localized labels. English values MUST stay byte-identical to the original
  // literals so the 92 EN pages' prepared static shells remain fresh; `zh`
  // supplies the Chinese mirror. Dropdown destinations are shared EN pages
  // (not yet translated), so only labels/descriptions localize there; the two
  // translated top-level pages + the brand link swap to their `-zh` targets.
  function STR(lang) {
    var zh = lang === 'zh';
    return {
      home: zh ? 'index-zh.html' : 'index.html',
      overview: zh ? '概览' : 'Overview',
      login: zh ? '登录' : 'Log in',
      startFree: zh ? '免费开始' : 'Start free',
      company: zh ? '公司' : 'Company',
      services: zh ? '服务' : 'Services',
      engines: zh ? '研究引擎' : 'Research Engines',
      evidence: zh ? '证据' : 'Evidence',
      // Dropdown groups: [label, description, [subLabel, subHref]...] — href shared.
      groups: {
        company: [
          { label: zh ? '关于 BioMate' : 'About BioMate', href: 'about.html', description: zh ? '我们的使命，以及我们对 AI 驱动科学的理念。' : 'Our mission and approach to AI-powered science.', links: [
            { label: zh ? 'BioMate 与其他方案的对比' : 'BioMate vs. the alternatives', href: 'compare.html' }
          ] },
          { label: zh ? '新闻中心' : 'Newsroom', href: 'blog.html?cat=news', description: zh ? '公司动态与团队最新进展。' : 'Company news and the latest from our team.' },
          { label: zh ? '联系我们' : 'Contact', href: 'contact.html', description: zh ? '交流你的研究，探讨与 BioMate 的合作。' : 'Discuss your research and working with BioMate.' }
        ],
        services: [
          { label: zh ? '生物医学研究平台' : 'Biomedical Research Platform', href: 'features.html', description: zh ? '从科学问题到可复现的分析。' : 'From scientific questions to reproducible analyses.', links: [
            { label: zh ? '探索应用场景' : 'Explore applications', href: 'services.html' },
            { label: zh ? '连接器与开发者文档' : 'Connectors & developer docs', href: 'connectors.html' }
          ] },
          { label: zh ? '药物发现' : 'Drug Discovery', href: 'drug-discovery.html', description: zh ? '靶点情报、分子设计与候选评估。' : 'Target intelligence, molecular design and candidate evaluation.', links: [
            { label: zh ? '探索工作台' : 'Explore the workbench', href: 'drug-discovery.html' }
          ] },
          { label: zh ? '快速上手' : 'Getting Started', href: 'tutorials.html', description: zh ? '面向研究团队的实用指引。' : 'Practical guidance for your research team.', links: [
            { label: zh ? '教程' : 'Tutorials', href: 'tutorials.html' },
            { label: zh ? '价格' : 'Pricing', href: 'pricing.html' }
          ] }
        ],
        engines: [
          { label: zh ? '我们的研究计划' : 'Our Research Programs', href: 'research-engines.html', description: zh ? '推进对生物学的理解与分子设计。' : 'Advancing biological understanding and molecular design.' },
          { label: zh ? '虚拟细胞大模型' : 'Virtual Cell LLM', href: 'research-engines.html#virtual-cell', description: zh ? '面向细胞状态、响应与疾病机制的研究。' : 'Research into cellular states, responses and disease mechanisms.' },
          { label: zh ? '环肽生成' : 'Cyclic-Peptide Generation', href: 'research-engines.html#cyclic-peptides', description: zh ? '面向结构感知生成与优化的研究。' : 'Research into structure-aware generation and optimization.' }
        ],
        research: [
          { label: zh ? '基准与评估' : 'Benchmarks & Evaluations', href: 'benchmarks.html', description: zh ? '查看性能、方法与评估标准。' : 'Inspect performance, methods and evaluation criteria.' },
          { label: zh ? '研究观点' : 'Research Perspectives', href: 'surveys.html', description: zh ? '探讨方法、比较与科学上的局限。' : 'Explore approaches, comparisons and scientific limitations.' },
          { label: zh ? '科学发表' : 'Scientific Publishing', href: 'publications.html', description: zh ? '关注研究及其应用。' : 'Follow the research and its applications.', links: [
            { label: zh ? '论文' : 'Publications', href: 'publications.html' },
            { label: zh ? '科学文章' : 'Scientific articles', href: 'blog.html?cat=science' }
          ] }
        ]
      }
    };
  }

  function navHTML(active, lang) {
    var s = STR(lang);
    // Company first; both workbenches belong to Services.
    var slugMap = {
      home: '', services: 'services', platform: 'services', drug: 'services',
      newsroom: 'company',
      pricing: 'services', about: 'company', contact: 'company', company: 'company',
      tutorials: 'research', benchmarks: 'research', research: 'research',
    };
    active = Object.prototype.hasOwnProperty.call(slugMap, active) ? slugMap[active] : active;

    function dropdown(slug, label, href, groups) {
      var isActive = active === slug;
      return `
        <li class="bm-has-dropdown">
          <button type="button" class="bm-nav-trigger ${isActive ? 'active' : ''}" aria-expanded="false" aria-controls="bm-panel-${slug}">${label}${chevron}</button>
          <div class="bm-dropdown" id="bm-panel-${slug}" inert>
            <div class="bm-dropdown-inner">
              <div class="bm-dropdown-grid">
                ${groups.map(function(group) {
                  return `<section class="bm-dropdown-group"><h2><a href="${group.href}">${group.label}</a></h2><p>${group.description}</p><ul>${(group.links || []).map(function(item) {
                    return `<li><a href="${item.href}">${item.label} &rarr;</a></li>`;
                  }).join('')}</ul></section>`;
                }).join('')}
              </div>
            </div>
          </div>
        </li>`;
    }

    return `
      <header class="bm-nav">
        <div class="bm-nav-inner">
          <a href="${s.home}" class="bm-brand" aria-label="BioMate AI">
            <img src="assets/logo.png?v=3" alt="BioMate AI" />
          </a>
          <nav aria-label="Primary navigation" class="bm-primary-nav"><ul class="bm-nav-links" id="bmNavLinks">
            ${dropdown('company', s.company, 'about.html', s.groups.company)}
            ${dropdown('services', s.services, 'services.html', s.groups.services)}
            ${dropdown('engines', s.engines, 'research-engines.html', s.groups.engines)}
            ${dropdown('research', s.evidence, 'benchmarks.html', s.groups.research)}
            <li><a href="https://dev-public.biomate.ai/login" class="bm-nav-login">${s.login}</a></li>
            <li><a href="https://dev-public.biomate.ai/register" class="bm-nav-cta">${s.startFree}</a></li>
          </ul></nav>
          <button class="bm-mobile-toggle" aria-label="Open menu" aria-expanded="false" aria-controls="bmNavLinks" id="bmMobileToggle">
            ${svg('<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="20" y2="17"/>')}
          </button>
        </div>
      </header>`;
  }

  function ctaHTML(lang) {
    var zh = lang === 'zh';
    return `
      <section class="bm-cta-bar">
        <div class="bm-cta-bar-inner">
          <p class="bm-cta-bar-eyebrow">BioMate AI</p>
          <h2 class="bm-cta-bar-head">${zh ? '免费试用 BioMate。' : 'Try BioMate free.'}</h2>
          <p class="bm-cta-bar-sub">${zh ? '从科学问题到可执行的结果，更快一步。' : 'Move faster from scientific question to actionable results.'}</p>
          <div class="bm-cta-bar-btns">
            <a href="https://dev-public.biomate.ai/register" class="bm-btn bm-btn-on-ink-primary bm-btn-lg">
              ${zh ? '免费开始' : 'Start free'} <span class="bm-btn-arrow">&rarr;</span>
            </a>
            <a href="contact.html?topic=General%20inquiry" class="bm-btn bm-btn-ink bm-btn-lg">${zh ? '联系我们' : 'Contact us'}</a>
          </div>
        </div>
      </section>`;
  }

  function footerHTML(lang) {
    var zh = lang === 'zh';
    var year = new Date().getFullYear();
    var home = zh ? 'index-zh.html' : 'index.html';
    return `
      <footer class="bm-footer">
        <div class="bm-footer-inner">
          <div class="bm-footer-grid">
            <div class="bm-footer-brand">
              <a href="${home}" class="bm-brand">
                <img src="assets/logo.png?v=3" alt="BioMate AI" />
              </a>
              <p>${zh ? '面向生物医学研究与药物发现的 AI 平台。' : 'The AI platform for biomedical research &amp; drug discovery.'}</p>
            </div>
            <div class="bm-footer-col">
              <h4>${zh ? '平台' : 'Platform'}</h4>
              <ul>
                <li><a href="features.html">${zh ? '研究工作台' : 'Research Workbench'}</a></li>
                <li><a href="drug-discovery.html">${zh ? '药物发现' : 'Drug Discovery'}</a></li>
                <li><a href="research-engines.html">${zh ? '研究引擎' : 'Research Engines'}</a></li>
                <li><a href="features.html">${zh ? '功能' : 'Features'}</a></li>
                <li><a href="benchmarks.html">${zh ? '基准' : 'Benchmarks'}</a></li>
                <li><a href="pricing.html">${zh ? '价格' : 'Pricing'}</a></li>
                <li><a href="https://dev-public.biomate.ai/register">${zh ? '免费开始' : 'Start free'}</a></li>
              </ul>
            </div>
            <div class="bm-footer-col">
              <h4>${zh ? '科学' : 'Science'}</h4>
              <ul>
                <li><a href="services.html#drug-discovery">${zh ? '药物发现' : 'Drug Discovery'}</a></li>
                <li><a href="services.html#genomics">${zh ? '基因组学与多组学' : 'Genomics &amp; Multi-Omics'}</a></li>
                <li><a href="services.html#structural-biology">${zh ? '结构生物学' : 'Structural Biology'}</a></li>
                <li><a href="surveys.html">${zh ? '研究观点' : 'Research Perspectives'}</a></li>
                <li><a href="blog.html">${zh ? '新闻中心' : 'Newsroom'} &rarr;</a></li>
              </ul>
            </div>
            <div class="bm-footer-col">
              <h4>${zh ? '公司' : 'Company'}</h4>
              <ul>
                <li><a href="about.html">${zh ? '关于' : 'About'}</a></li>
                <li><a href="tutorials.html">${zh ? '教程' : 'Tutorials'}</a></li>
                <li><a href="glossary.html">${zh ? '术语表' : 'Glossary'}</a></li>
                <li><a href="blog.html">${zh ? '新闻中心' : 'Newsroom'}</a></li>
                <li><a href="contact.html">${zh ? '联系我们' : 'Contact'}</a></li>
                <li><a href="mailto:contact@biomate.ai">contact@biomate.ai</a></li>
              </ul>
            </div>
          </div>
          <div class="bm-footer-bottom">
            <span>&copy; ${year} BioMate AI &middot; contact@biomate.ai</span>
            <span class="links">
              <a href="privacy.html">${zh ? '隐私' : 'Privacy'}</a>
              <a href="terms.html">${zh ? '条款' : 'Terms'}</a>
            </span>
          </div>
        </div>
      </footer>`;
  }

  // Static preparation and browser enhancement share one markup definition.
  if (typeof module === 'object' && module.exports) {
    module.exports = { navHTML: navHTML, ctaHTML: ctaHTML, footerHTML: footerHTML };
    return;
  }

  window.renderShell = function (opts) {
    var active = (opts && opts.active) || '';
    var showCta = (opts && opts.cta === false) ? false : true;
    var lang = (opts && opts.lang) || '';

    var navMount = document.getElementById('bm-nav');
    if (navMount) navMount.outerHTML = navHTML(active, lang);

    var footMount = document.getElementById('bm-foot');
    if (footMount) footMount.outerHTML = (showCta ? ctaHTML(lang) : '') + footerHTML(lang);

    var header = document.querySelector('.bm-nav');
    var dropdowns = Array.from(document.querySelectorAll('.bm-has-dropdown'));
    function setOpen(el, open) {
      el.classList.toggle('bm-dd-open', open);
      el.querySelector('.bm-nav-trigger').setAttribute('aria-expanded', String(open));
      el.querySelector('.bm-dropdown').toggleAttribute('inert', !open);
    }
    function closeAll() { dropdowns.forEach(function(el) { setOpen(el, false); }); }
    function openOnly(el) { closeAll(); setOpen(el, true); }

    document.addEventListener('click', function(e) {
      if (!e.target.closest('.bm-has-dropdown')) closeAll();
    });

    // Native disclosure buttons: click/touch toggles; links always navigate.
    dropdowns.forEach(function(el) {
      var button = el.querySelector('.bm-nav-trigger');
      button.addEventListener('click', function() {
        var open = button.getAttribute('aria-expanded') === 'true';
        closeAll();
        if (!open) setOpen(el, true);
      });
      button.addEventListener('keydown', function(e) {
        if (e.key === 'ArrowDown') {
          e.preventDefault(); openOnly(el);
          el.querySelector('.bm-dropdown a').focus();
        }
      });
      el.addEventListener('focusout', function(e) {
        // On touch layouts, collapsing before another trigger's click moves that
        // trigger under the pointer. Let the click switch sections atomically.
        if (window.innerWidth <= 900 && header.contains(e.relatedTarget)) return;
        if (!el.contains(e.relatedTarget)) setOpen(el, false);
      });
      // Opening is deliberate: no hover-only state that disagrees with aria-expanded.
      el.querySelectorAll('.bm-dropdown a').forEach(function(a) {
        a.addEventListener('click', function() {
          closeAll();
          if (window.innerWidth <= 900) setMobile(false);
        });
      });
    });

    // ── Mobile toggle ──
    var tog = document.getElementById('bmMobileToggle');
    var links = document.getElementById('bmNavLinks');
    function setMobile(open) {
      if (!tog || !links) return;
      tog.setAttribute('aria-expanded', String(open));
      tog.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
      links.classList.toggle('bm-nav-open', open);
      if (!open) closeAll();
    }
    if (tog && links) {
      tog.addEventListener('click', function() {
        setMobile(tog.getAttribute('aria-expanded') !== 'true');
      });
    }
    document.addEventListener('keydown', function(e) {
      if (e.key !== 'Escape') return;
      var open = header && header.querySelector('.bm-dd-open');
      if (open) { closeAll(); open.querySelector('.bm-nav-trigger').focus(); }
      else if (links && links.classList.contains('bm-nav-open')) { setMobile(false); tog.focus(); }
    });
    document.addEventListener('click', function(e) {
      if (header && !header.contains(e.target)) setMobile(false);
    });
    window.matchMedia('(max-width: 900px)').addEventListener('change', function() { setMobile(false); });
  };
})();
