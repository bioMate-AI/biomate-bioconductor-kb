/* Shared nav + footer rendering for BioMate v2.
   Inject by calling renderShell({ active: 'home' | 'features' | 'pricing' | 'about' | 'blog' }). */

(function () {
  function svg(d, vb) {
    return `<svg viewBox="${vb || '0 0 24 24'}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  }

  function navHTML(active) {
    const link = (slug, label, href) =>
      `<li><a href="${href}" class="${active === slug ? 'active' : ''}">${label}</a></li>`;
    return `
      <header class="bm-nav">
        <div class="bm-nav-inner">
          <a href="index.html" class="bm-brand" aria-label="BioMate AI">
            <img src="assets/logo.png" alt="BioMate AI" />
          </a>
          <ul class="bm-nav-links">
            ${link('home', 'Home', 'index.html')}
            ${link('features', 'Features', 'features.html')}
            ${link('pricing', 'Pricing', 'pricing.html')}
            ${link('about', 'About', 'about.html')}
            ${link('blog', 'Blog', 'blog.html')}
            <li><a href="https://dev-public.biomate.ai/login" class="bm-nav-login">Log in</a></li>
            <li><a href="https://dev-public.biomate.ai/register" class="bm-nav-cta">Start free</a></li>
          </ul>
          <button class="bm-mobile-toggle" aria-label="Open menu" id="bmMobileToggle">
            ${svg('<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="20" y2="17"/>')}
          </button>
        </div>
      </header>`;
  }

  function footerHTML() {
    const year = new Date().getFullYear();
    return `
      <footer class="bm-footer">
        <div class="bm-footer-inner">
          <div class="bm-footer-grid">
            <div class="bm-footer-brand">
              <a href="index.html" class="bm-brand">
                <img src="assets/logo.png" alt="BioMate AI" />
              </a>
              <p>Computational platform for pharma, biotech, academic labs, and core facilities.</p>
            </div>
            <div class="bm-footer-col">
              <h4>Product</h4>
              <ul>
                <li><a href="features.html">Features</a></li>
                <li><a href="pricing.html">Pricing</a></li>
                <li><a href="https://dev-public.biomate.ai/register">Start free</a></li>
              </ul>
            </div>
            <div class="bm-footer-col">
              <h4>Science</h4>
              <ul>
                <li><a href="blog-drug-1-target.html">Target Discovery</a></li>
                <li><a href="blog-drug-3-admet.html">ADMET &amp; Lead Optimization</a></li>
                <li><a href="blog-cryosparc-spa.html">Cryo-EM</a></li>
                <li><a href="blog-gatk-deepvariant.html">Genomics</a></li>
                <li><a href="blog.html">All topics &rarr;</a></li>
              </ul>
            </div>
            <div class="bm-footer-col">
              <h4>Company</h4>
              <ul>
                <li><a href="about.html">About</a></li>
                <li><a href="blog.html">Blog</a></li>
                <li><a href="mailto:contact@biomate.ai">Contact</a></li>
              </ul>
            </div>
          </div>
          <div class="bm-footer-bottom">
            <span>&copy; ${year} BioMate AI &middot; contact@biomate.ai</span>
            <span class="links">
              <a href="https://dev-public.biomate.ai/privacy" target="_blank" rel="noopener">Privacy</a>
              <a href="https://dev-public.biomate.ai/terms" target="_blank" rel="noopener">Terms</a>
            </span>
          </div>
        </div>
      </footer>`;
  }

  window.renderShell = function ({ active }) {
    const navMount = document.getElementById('bm-nav');
    const footMount = document.getElementById('bm-foot');
    if (navMount) navMount.outerHTML = navHTML(active);
    if (footMount) footMount.outerHTML = footerHTML();

    // Mobile toggle (very minimal — collapses links into a stack)
    const tog = document.getElementById('bmMobileToggle');
    if (tog) {
      tog.addEventListener('click', () => {
        const links = document.querySelector('.bm-nav-links');
        if (!links) return;
        const open = links.style.display === 'flex' && links.style.position === 'fixed';
        if (open) {
          links.removeAttribute('style');
        } else {
          Object.assign(links.style, {
            display: 'flex', flexDirection: 'column', position: 'fixed',
            top: '64px', left: '0', right: '0', background: 'var(--bg)',
            borderBottom: '1px solid var(--border)', padding: '1rem',
            gap: '.25rem', zIndex: 99
          });
        }
      });
    }
  };
})();
