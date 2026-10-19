/* Shared nav + footer + CTA rendering for BioMate v2.
   Call renderShell({ active: 'home'|'services'|'newsroom'|'pricing'|'about'|'contact' }) */

(function () {
  function svg(d, vb) {
    return `<svg viewBox="${vb || '0 0 24 24'}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  }

  var chevron = `<svg class="bm-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9"/></svg>`;

  function navHTML(active) {
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
              <div class="bm-dropdown-heading"><span>${label}</span><a href="${href}">Overview &rarr;</a></div>
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
          <a href="index.html" class="bm-brand" aria-label="BioMate AI">
            <img src="assets/logo.png?v=3" alt="BioMate AI" />
          </a>
          <nav aria-label="Primary navigation" class="bm-primary-nav"><ul class="bm-nav-links" id="bmNavLinks">
            <li><a class="bm-nav-trigger${active === 'therapeutic-areas' ? ' active' : ''}" href="therapeutic-areas.html">Therapeutic Areas</a></li>
            <li><a class="bm-nav-trigger${active === 'how-we-design' ? ' active' : ''}" href="how-we-design.html">How We Design</a></li>
            ${dropdown('company', 'Company', 'about.html', [
              { label: 'About BioMate', href: 'about.html', description: 'Our mission and approach to AI-powered science.', links: [
                { label: 'BioMate vs. the alternatives', href: 'compare.html' }
              ] },
              { label: 'Newsroom', href: 'blog.html?cat=news', description: 'Company news and the latest from our team.' },
              { label: 'Contact', href: 'contact.html', description: 'Discuss your research and working with BioMate.' }
            ])}
            ${dropdown('services', 'Services', 'services.html', [
              { label: 'Biomedical Research Platform', href: 'features.html', description: 'From scientific questions to reproducible analyses.', links: [
                { label: 'Explore applications', href: 'services.html' },
                { label: 'Connectors & developer docs', href: 'connectors.html' }
              ] },
              { label: 'Drug Discovery', href: 'drug-discovery.html', description: 'Target intelligence, molecular design and candidate evaluation.', links: [
                { label: 'Explore the workbench', href: 'drug-discovery.html' }
              ] },
              { label: 'Getting Started', href: 'tutorials.html', description: 'Practical guidance for your research team.', links: [
                { label: 'Tutorials', href: 'tutorials.html' },
                { label: 'Pricing', href: 'pricing.html' }
              ] }
            ])}
            ${dropdown('engines', 'Research Engines', 'research-engines.html', [
              { label: 'Our Research Programs', href: 'research-engines.html', description: 'Advancing biological understanding and molecular design.' },
              { label: 'Virtual Cell LLM', href: 'research-engines.html#virtual-cell', description: 'Research into cellular states, responses and disease mechanisms.' },
              { label: 'Cyclic-Peptide Generation', href: 'research-engines.html#cyclic-peptides', description: 'Research into structure-aware generation and optimization.' }
            ])}
            ${dropdown('research', 'Evidence', 'benchmarks.html', [
              { label: 'Benchmarks & Evaluations', href: 'benchmarks.html', description: 'Inspect performance, methods and evaluation criteria.' },
              { label: 'Research Perspectives', href: 'surveys.html', description: 'Explore approaches, comparisons and scientific limitations.' },
              { label: 'Scientific Publishing', href: 'publications.html', description: 'Follow the research and its applications.', links: [
                { label: 'Publications', href: 'publications.html' },
                { label: 'Scientific articles', href: 'blog.html?cat=science' }
              ] }
            ])}
            <li><a href="https://dev-public.biomate.ai/login" class="bm-nav-login">Log in</a></li>
            <li><a href="https://dev-public.biomate.ai/register" class="bm-nav-cta">Start free</a></li>
          </ul></nav>
          <button class="bm-mobile-toggle" aria-label="Open menu" aria-expanded="false" aria-controls="bmNavLinks" id="bmMobileToggle">
            ${svg('<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="20" y2="17"/>')}
          </button>
        </div>
      </header>`;
  }

  function ctaHTML() {
    return `
      <section class="bm-cta-bar">
        <div class="bm-cta-bar-inner">
          <p class="bm-cta-bar-eyebrow">BioMate AI</p>
          <h2 class="bm-cta-bar-head">Try BioMate free.</h2>
          <p class="bm-cta-bar-sub">Move faster from scientific question to actionable results.</p>
          <div class="bm-cta-bar-btns">
            <a href="https://dev-public.biomate.ai/register" class="bm-btn bm-btn-on-ink-primary bm-btn-lg">
              Start free <span class="bm-btn-arrow">&rarr;</span>
            </a>
            <a href="contact.html?topic=General%20inquiry" class="bm-btn bm-btn-ink bm-btn-lg">Contact us</a>
          </div>
        </div>
      </section>`;
  }

  function footerHTML() {
    var year = new Date().getFullYear();
    return `
      <footer class="bm-footer">
        <div class="bm-footer-inner">
          <div class="bm-footer-grid">
            <div class="bm-footer-brand">
              <a href="index.html" class="bm-brand">
                <img src="assets/logo.png?v=3" alt="BioMate AI" />
              </a>
              <p>The AI platform for biomedical research &amp; drug discovery.</p>
            </div>
            <div class="bm-footer-col">
              <h4>Platform</h4>
              <ul>
                <li><a href="features.html">Research Workbench</a></li>
                <li><a href="drug-discovery.html">Drug Discovery</a></li>
                <li><a href="research-engines.html">Research Engines</a></li>
                <li><a href="features.html">Features</a></li>
                <li><a href="benchmarks.html">Benchmarks</a></li>
                <li><a href="pricing.html">Pricing</a></li>
                <li><a href="https://dev-public.biomate.ai/register">Start free</a></li>
              </ul>
            </div>
            <div class="bm-footer-col">
              <h4>Science</h4>
              <ul>
                <li><a href="services.html#drug-discovery">Drug Discovery</a></li>
                <li><a href="services.html#genomics">Genomics &amp; Multi-Omics</a></li>
                <li><a href="services.html#structural-biology">Structural Biology</a></li>
                <li><a href="surveys.html">Research Perspectives</a></li>
                <li><a href="blog.html">Newsroom &rarr;</a></li>
              </ul>
            </div>
            <div class="bm-footer-col">
              <h4>Company</h4>
              <ul>
                <li><a href="about.html">About</a></li>
                <li><a href="tutorials.html">Tutorials</a></li>
                <li><a href="glossary.html">Glossary</a></li>
                <li><a href="blog.html">Newsroom</a></li>
                <li><a href="contact.html">Contact</a></li>
                <li><a href="mailto:contact@biomate.ai">contact@biomate.ai</a></li>
              </ul>
            </div>
          </div>
          <div class="bm-footer-bottom">
            <span>&copy; ${year} BioMate AI &middot; contact@biomate.ai</span>
            <span class="links">
              <a href="privacy.html">Privacy</a>
              <a href="terms.html">Terms</a>
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

    var navMount = document.getElementById('bm-nav');
    if (navMount) navMount.outerHTML = navHTML(active);

    var footMount = document.getElementById('bm-foot');
    if (footMount) footMount.outerHTML = (showCta ? ctaHTML() : '') + footerHTML();

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
