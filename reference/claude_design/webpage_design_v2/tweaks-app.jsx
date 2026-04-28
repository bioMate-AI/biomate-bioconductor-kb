/* eslint-disable */
// Tweaks panel — site-wide design knobs.
// Reads/writes the EDITMODE block in this file via the host (no need for separate state).

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "palette": "default",
  "type": "default",
  "density": "cozy",
  "appsMode": "photo",
  "showStats": true,
  "showCTA": true,
  "showTestimonials": true,
  "ctaStyle": "gradient",
  "approachStyle": "list",
  "heroAccent": "navy"
}/*EDITMODE-END*/;

const PALETTE_LABEL = {
  default:    'Cream + Brand Navy',
  leaf:       'Cream + Leaf Green',
  terracotta: 'Cream + Warm Gold',
  deepnavy:   'Deep Navy + Cream'
};
const TYPE_LABEL = {
  default: 'Crimson + Open Sans',
  modern: 'Source Serif + Inter',
  editorial: 'Instrument Serif + Inter',
  'all-sans': 'Inter (all sans)'
};

function applyTweaks(t) {
  const html = document.documentElement;
  html.dataset.palette = t.palette;
  html.dataset.type = t.type;
  html.dataset.density = t.density;

  // Re-render app cards if mode changed and the grid is on this page
  if (typeof renderAppCards === 'function') {
    const grid = document.getElementById('bm-apps-grid');
    if (grid) renderAppCards('bm-apps-grid', t.appsMode);
  }

  // Toggle optional homepage sections
  document.querySelectorAll('[data-tw-section]').forEach((el) => {
    const key = el.dataset.twSection;
    if (key === 'stats')        el.style.display = t.showStats ? '' : 'none';
    if (key === 'cta')          el.style.display = t.showCTA ? '' : 'none';
    if (key === 'testimonials') el.style.display = t.showTestimonials ? '' : 'none';
  });

  // CTA banner style
  const cta = document.querySelector('.bm-cta-banner');
  if (cta) {
    cta.classList.toggle('bm-cta-flat', t.ctaStyle === 'flat');
    cta.classList.toggle('bm-cta-ink',  t.ctaStyle === 'ink');
  }

  // Approach: swap list <-> cards
  const approachMount = document.getElementById('bm-approach-mount');
  if (approachMount && approachMount.dataset.original === undefined) {
    approachMount.dataset.original = approachMount.outerHTML;
  }
  if (approachMount) {
    if (t.approachStyle === 'cards') {
      const items = [...approachMount.querySelectorAll('.bm-approach-item, li')].map((li) => {
        const h = li.querySelector('h4')?.innerText || '';
        const p = li.querySelector('p')?.innerHTML  || '';
        return { h, p };
      });
      // Build cards markup
      const ICONS = ['data','shield','brain','cloud','community','globe'];
      const html = `
        <div class="bm-approach-cards">
          ${items.map((it, i) => `
            <article class="bm-approach-card">
              <div class="bm-icon-wrap">${(window.BM_ICON && window.BM_ICON[ICONS[i % ICONS.length]]) || ''}</div>
              <h4>${it.h}</h4>
              <p>${it.p}</p>
            </article>
          `).join('')}
        </div>`;
      // Replace contents only if not already in cards mode
      if (!approachMount.querySelector('.bm-approach-cards')) {
        approachMount.innerHTML = html;
        approachMount.classList.remove('bm-approach-list');
      }
    } else {
      // back to list — restore from original
      if (approachMount.querySelector('.bm-approach-cards')) {
        const tmp = document.createElement('div');
        tmp.innerHTML = approachMount.dataset.original;
        approachMount.outerHTML = tmp.firstElementChild.outerHTML;
      }
    }
  }
}

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);

  React.useEffect(() => { applyTweaks(t); }, [t]);

  return (
    <TweaksPanel title="Tweaks">
      <TweakSection label="Palette &amp; voice" />
      <TweakSelect
        label="Color palette"
        value={t.palette}
        options={Object.keys(PALETTE_LABEL).map((k) => ({ value: k, label: PALETTE_LABEL[k] }))}
        onChange={(v) => setTweak('palette', v)}
      />
      <TweakSelect
        label="Type pairing"
        value={t.type}
        options={Object.keys(TYPE_LABEL).map((k) => ({ value: k, label: TYPE_LABEL[k] }))}
        onChange={(v) => setTweak('type', v)}
      />
      <TweakRadio
        label="Density"
        value={t.density}
        options={['compact', 'cozy', 'generous']}
        onChange={(v) => setTweak('density', v)}
      />

      <TweakSection label="Application cards" />
      <TweakRadio
        label="Visualization style"
        value={t.appsMode}
        options={[
          { value: 'illustration', label: 'Drawn' },
          { value: 'photo',        label: 'Photo' }
        ]}
        onChange={(v) => setTweak('appsMode', v)}
      />

      <TweakSection label="Sections" />
      <TweakToggle label="Show stats strip"  value={t.showStats}        onChange={(v) => setTweak('showStats', v)} />
      <TweakToggle label="Show testimonials" value={t.showTestimonials} onChange={(v) => setTweak('showTestimonials', v)} />
      <TweakToggle label="Show CTA banner"   value={t.showCTA}          onChange={(v) => setTweak('showCTA', v)} />

      <TweakSection label="Components" />
      <TweakRadio
        label="Approach layout"
        value={t.approachStyle}
        options={[
          { value: 'list',  label: 'Editorial list' },
          { value: 'cards', label: 'Icon cards' }
        ]}
        onChange={(v) => setTweak('approachStyle', v)}
      />
      <TweakRadio
        label="CTA banner style"
        value={t.ctaStyle}
        options={[
          { value: 'gradient', label: 'Gradient' },
          { value: 'flat',     label: 'Flat' },
          { value: 'ink',      label: 'Ink' }
        ]}
        onChange={(v) => setTweak('ctaStyle', v)}
      />
    </TweaksPanel>
  );
}

// Tag the homepage sections so the toggles can find them.
(function tagSections() {
  const stats = document.querySelector('.bm-stats');
  if (stats) stats.dataset.twSection = 'stats';
  document.querySelectorAll('.bm-section').forEach((s) => {
    if (s.querySelector('.bm-cta-banner')) s.dataset.twSection = 'cta';
    if (s.querySelector('.bm-testimonials')) s.dataset.twSection = 'testimonials';
  });
})();

// Mount
const __mount = document.createElement('div');
document.body.appendChild(__mount);
ReactDOM.createRoot(__mount).render(<App />);
