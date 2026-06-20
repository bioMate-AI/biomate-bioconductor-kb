/* Shared nav + footer + CTA rendering for BioMate v2.
   Call renderShell({ active: 'home'|'services'|'newsroom'|'pricing'|'about'|'contact' }) */

(function () {
  function svg(d, vb) {
    return `<svg viewBox="${vb || '0 0 24 24'}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  }

  var chevron = `<svg class="bm-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9"/></svg>`;

  function navHTML(active) {
    function link(slug, label, href) {
      return `<li><a href="${href}" class="${active === slug ? 'active' : ''}">${label}</a></li>`;
    }
    function dropdown(slug, label, href, items) {
      var isActive = active === slug || items.some(function(i){ return i.active; });
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
            <img src="assets/logo.png" alt="BioMate AI" />
          </a>
          <ul class="bm-nav-links" id="bmNavLinks">
            ${link('home', 'Home', 'index.html')}
            ${dropdown('services', 'Services', 'services.html', [
              { label: 'Drug Discovery',           href: 'services.html#drug-discovery' },
              { label: 'Genomics &amp; Multi-Omics', href: 'services.html#genomics' },
              { label: 'Structural Biology',       href: 'services.html#structural-biology' },
              { divider: true },
              { label: 'All Services &rarr;',      href: 'services.html', bold: true }
            ])}
            ${dropdown('newsroom', 'Newsroom', 'blog.html', [
              { label: 'Scientific Articles', href: 'blog.html?cat=science' },
              { label: 'Company News',        href: 'blog.html?cat=news' },
              { label: 'Publications',        href: 'publications.html' },
              { divider: true },
              { label: 'All Posts &rarr;',    href: 'blog.html', bold: true }
            ])}
            ${link('pricing', 'Pricing', 'pricing.html')}
            ${dropdown('about', 'About', 'about.html', [
              { label: 'About BioMate',      href: 'about.html' },
              { label: 'Platform Features',  href: 'features.html' },
              { label: 'Compare',            href: 'compare.html' }
              /* Team — commented out until team page is ready
              ,{ label: 'Team',              href: 'team.html' }
              */
            ])}
            ${link('tutorials', 'Tutorials', 'tutorials.html')}
            ${link('contact', 'Contact', 'contact.html')}
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
          <p class="bm-cta-bar-sub">The computational biology assistant for pharma, biotech, and academic labs.</p>
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
                <img src="assets/logo.png" alt="BioMate AI" />
              </a>
              <p>Computational biology assistant for pharma, biotech, academic labs, and core facilities.</p>
            </div>
            <div class="bm-footer-col">
              <h4>Platform</h4>
              <ul>
                <li><a href="services.html">Services</a></li>
                <li><a href="features.html">Features</a></li>
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

    // ── Dropdown: toggle on click (also works for touch) ──
    document.querySelectorAll('.bm-has-dropdown > a').forEach(function(a) {
      a.addEventListener('click', function(e) {
        var li = a.closest('.bm-has-dropdown');
        var isOpen = li.classList.contains('bm-dd-open');
        document.querySelectorAll('.bm-has-dropdown').forEach(function(el) {
          el.classList.remove('bm-dd-open');
        });
        if (!isOpen) {
          li.classList.add('bm-dd-open');
          // Only prevent default when opening the dropdown itself (not navigating)
          if (window.innerWidth > 900) e.preventDefault();
        }
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
      });

      // Mobile: expand/collapse dropdowns as accordions
      links.querySelectorAll('.bm-has-dropdown > a').forEach(function(a) {
        a.addEventListener('click', function(e) {
          if (window.innerWidth <= 900) {
            e.preventDefault();
            var li = a.closest('.bm-has-dropdown');
            li.classList.toggle('bm-dd-open');
          }
        });
      });
    }
  };
})();
