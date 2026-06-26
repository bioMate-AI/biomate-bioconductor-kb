/* Shared nav + footer + CTA rendering for BioMate v2.
   Call renderShell({ active: 'home'|'services'|'newsroom'|'pricing'|'about'|'contact' }) */

(function () {
  function svg(d, vb) {
    return `<svg viewBox="${vb || '0 0 24 24'}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  }

  var chevron = `<svg class="bm-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9"/></svg>`;

  function navHTML(active) {
    // Normalize legacy active slugs → 4-group structure
    var slugMap = {
      home: '', services: 'platform', platform: 'platform',
      newsroom: 'newsroom',
      pricing: 'company', about: 'company', contact: 'company', company: 'company',
      tutorials: 'research', benchmarks: 'research', research: 'research',
    };
    active = Object.prototype.hasOwnProperty.call(slugMap, active) ? slugMap[active] : active;

    function dropdown(slug, label, href, items) {
      var isActive = active === slug;
      return `
        <li class="bm-has-dropdown">
          <a href="${href}" class="${isActive ? 'active' : ''}">${label}${chevron}</a>
          <ul class="bm-dropdown" role="menu">
            ${items.map(function(item) {
              if (item.divider) return `<li class="bm-dropdown-divider" role="separator"></li>`;
              return `<li role="none"><a href="${item.href}" role="menuitem"${item.bold ? ' style="font-weight:600"' : ''}>${item.label}</a></li>`;
            }).join('')}
          </ul>
        </li>`;
    }

    return `
      <header class="bm-nav">
        <div class="bm-nav-inner">
          <a href="index.html" class="bm-brand" aria-label="BioMate AI">
            <img src="assets/logo.png?v=3" alt="BioMate AI" />
          </a>
          <ul class="bm-nav-links" id="bmNavLinks">
            <li><a href="index.html" class="${active === '' ? 'active' : ''}">Home</a></li>
            ${dropdown('platform', 'Platform', 'services.html', [
              { label: 'Platform Features',          href: 'features.html' },
              { divider: true },
              { label: 'Drug Discovery',             href: 'services.html#drug-discovery' },
              { label: 'Genomics &amp; Multi-Omics', href: 'services.html#genomics' },
              { label: 'Structural Biology',         href: 'services.html#structural-biology' },
              { divider: true },
              { label: 'All Services &rarr;',        href: 'services.html', bold: true }
            ])}
            ${dropdown('research', 'Research', 'benchmarks.html', [
              { label: 'Benchmarks',   href: 'benchmarks.html' },
              { label: 'Tutorials',    href: 'tutorials.html' },
              { label: 'Publications', href: 'publications.html' }
            ])}
            ${dropdown('newsroom', 'Newsroom', 'blog.html', [
              { label: 'Scientific Articles', href: 'blog.html?cat=science' },
              { label: 'Company News',        href: 'blog.html?cat=news' },
              { divider: true },
              { label: 'All Posts &rarr;',    href: 'blog.html', bold: true }
            ])}
            ${dropdown('company', 'Company', 'about.html', [
              { label: 'About BioMate', href: 'about.html' },
              { label: 'Pricing',       href: 'pricing.html' },
              { label: 'Compare',       href: 'compare.html' },
              { divider: true },
              { label: 'Contact',       href: 'contact.html' }
            ])}
            <li><a href="https://dev-public.biomate.ai/login" class="bm-nav-login">Log in</a></li>
            <li><a href="https://dev-public.biomate.ai/register" class="bm-nav-cta">Start free</a></li>
          </ul>
          <button class="bm-mobile-toggle" aria-label="Open menu" aria-expanded="false" id="bmMobileToggle">
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
          <p class="bm-cta-bar-sub">The agentic AI assistant for biomedical research.</p>
          <div class="bm-cta-bar-btns">
            <a href="https://dev-public.biomate.ai/register" class="bm-btn bm-btn-on-ink-primary bm-btn-lg">
              Start free <span class="bm-btn-arrow">&rarr;</span>
            </a>
            <a href="contact.html" class="bm-btn bm-btn-ink bm-btn-lg">Contact us</a>
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
              <p>Agentic AI assistant for biomedical research.</p>
            </div>
            <div class="bm-footer-col">
              <h4>Platform</h4>
              <ul>
                <li><a href="services.html">Services</a></li>
                <li><a href="features.html">Features</a></li>
                <li><a href="benchmarks.html">Benchmarks</a></li>
                <li><a href="pricing.html">Pricing</a></li>
                <li><a href="compare.html">Compare</a></li>
                <li><a href="https://dev-public.biomate.ai/register">Start free</a></li>
              </ul>
            </div>
            <div class="bm-footer-col">
              <h4>Science</h4>
              <ul>
                <li><a href="services.html#drug-discovery">Drug Discovery</a></li>
                <li><a href="services.html#genomics">Genomics &amp; Multi-Omics</a></li>
                <li><a href="services.html#structural-biology">Structural Biology</a></li>
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

  window.renderShell = function (opts) {
    var active = (opts && opts.active) || '';
    var showCta = (opts && opts.cta === false) ? false : true;

    var navMount = document.getElementById('bm-nav');
    if (navMount) navMount.outerHTML = navHTML(active);

    var footMount = document.getElementById('bm-foot');
    if (footMount) footMount.outerHTML = (showCta ? ctaHTML() : '') + footerHTML();

    // ── Dropdown: close when clicking outside ──
    document.addEventListener('click', function(e) {
      if (!e.target.closest('.bm-has-dropdown')) {
        document.querySelectorAll('.bm-has-dropdown').forEach(function(el) {
          el.classList.remove('bm-dd-open');
        });
      }
    });

    // ── Dropdown: single unified toggle (desktop + mobile, one listener per element) ──
    document.querySelectorAll('.bm-has-dropdown > a').forEach(function(a) {
      a.addEventListener('click', function(e) {
        var li = a.closest('.bm-has-dropdown');
        var isOpen = li.classList.contains('bm-dd-open');
        var isMobileNav = window.innerWidth <= 900;
        // Close all other dropdowns first
        document.querySelectorAll('.bm-has-dropdown').forEach(function(el) {
          if (el !== li) el.classList.remove('bm-dd-open');
        });
        if (!isOpen) {
          li.classList.add('bm-dd-open');
          // Prevent navigation on both desktop and mobile when opening dropdown
          e.preventDefault();
        } else if (isMobileNav) {
          // Mobile: close accordion, never navigate
          li.classList.remove('bm-dd-open');
          e.preventDefault();
        }
        // Desktop + already open: allow navigation to the section href
      });
    });

    // ── Mobile toggle ──
    var tog = document.getElementById('bmMobileToggle');
    var links = document.getElementById('bmNavLinks');
    if (tog && links) {
      tog.addEventListener('click', function() {
        var open = tog.getAttribute('aria-expanded') === 'true';
        tog.setAttribute('aria-expanded', open ? 'false' : 'true');
        links.classList.toggle('bm-nav-open', !open);
        // Close all dropdowns when closing the mobile menu
        if (open) {
          links.querySelectorAll('.bm-has-dropdown').forEach(function(el) {
            el.classList.remove('bm-dd-open');
          });
        }
      });
    }
  };
})();
