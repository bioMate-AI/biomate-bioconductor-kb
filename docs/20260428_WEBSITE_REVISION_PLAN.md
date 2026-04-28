# Website Revision Plan — 2026-04-28

## Context

User's mentor (Illumina/GRAIL/Merck as references) reviewed the current biomate.ai website and gave feedback:

1. Add a Services page — clients don't know what BioMate does
2. Move Features content under About; remove Features from top nav
3. Add Newsroom category (rename Blog)
4. CTA on every page: "Try BioMate free" (NOT "no credit card")
5. Add Contact page
6. Hero wording: "A new type of partner…" → "BioMate is a computational biology assistant"
7. Survey regulatory compliance before offering it as a named service

---

## 1. Regulatory Gap Analysis (agent completed 2026-04-28)

### Finding: DO NOT list "Regulatory Compliance" as a named service yet.

Full 21 CFR Part 11 compliance requires:
- **Investment**: $1.1M–$1.9M one-time + $250–400K/year maintenance
- **Timeline**: 24–36 months
- **Gap**: BioMate is currently ~15–20% compliant (has basic audit trail, user ID logging, QC logging — missing electronic signatures, system validation docs, SOPs, workflow validation, immutable audit trail architecture)

Competitors (Benchling, Dotmatics, Veeva) completed this 10–15 years ago and charge $50–200K+/year for it.

### What BioMate CAN truthfully say:
- "Complete audit trail on every run"
- "Evidence-graded QC with published citations"
- "Submission-ready Methods section auto-generated"
- "Outputs designed to support regulatory filings"

### What to avoid:
- "Regulatory Compliance" as a service name
- "21 CFR Part 11 compliant" (not yet)
- "FDA-validated workflows" (not certified)

---

## 2. Agreed Nav Structure

**Current**: `Home | Features | Pricing | About | Blog`

**New**: `Home | Services ▾ | Newsroom ▾ | Pricing | About ▾ | Contact | [Log in] [Start free]`

### Services dropdown
- Drug Discovery (target → preclinical → clinical → PV)
- Genomics & Multi-Omics (WGS, RNA-seq, scRNA-seq, ATAC-seq, etc.)
- Structural Biology (cryo-EM SPA, AlphaFold, MD)
- All Services →

### Newsroom dropdown
- Scientific Articles (workflow/method deep-dives)
- Company News (platform updates)
- *(Blog is renamed Newsroom; files stay as blog-*.html)*

### About dropdown
- About BioMate
- How It Works
- Platform Features (moves features.html content here)
- Team

### Notes
- Pricing stays as top-level link (no dropdown)
- Contact stays as top-level link (no dropdown)
- Features removed as standalone top-level nav item
- features.html stays accessible via URL and About submenu link
- blog.html stays accessible, just relabeled Newsroom in nav

---

## 3. Universal CTA Bar

Added to the bottom of every page, above the footer.

Content:
```
Try BioMate free          [Start free →]   [Contact us]
The computational biology assistant for pharma, biotech, and academic labs.
```

Style: cream background `#f6efde`, navy text `#14283a`, accent CTA button `#2a5582`

---

## 4. New Pages to Create

### `services.html`
Hero: "What BioMate does."
Content sections:
1. **Drug Discovery** — target discovery, hit screening, ADMET/DMPK, lead optimization, PBPK, clinical pharmacology, pharmacovigilance. Outputs: scored ligands, ADMET panels, PK profiles, methods drafts.
2. **Genomics & Multi-Omics** — WGS, WES, RNA-seq, scRNA-seq, ATAC-seq, ChIP-seq, proteomics, metabolomics, metagenomics. Outputs: annotated VCF, differential expression, pathway analysis, QC reports.
3. **Structural Biology** — cryo-EM SPA (CryoSPARC), protein structure (AlphaFold3), molecular dynamics (GROMACS), docking (AutoDock Vina, DiffDock). Outputs: refined maps, structures, binding scores.
4. **Cross-Service Capabilities** — audit trail on every run, evidence-graded QC (Gold/Silver/Bronze), AI-generated Methods section, GPU cloud execution, 2,000+ validated workflows.

NOT included: Regulatory Compliance (per gap analysis)

### `contact.html`
- Email: contact@biomate.ai
- Form: name, email, organization, message, submit
- For enterprise/CRO inquiries: separate note
- Address / location (if applicable)

### `newsroom.html`
- Rename/alias for blog.html
- Same content as blog.html but with updated title "Newsroom" and categories: Scientific Articles, Company News
- OR: update blog.html itself to say "Newsroom" in the hero

---

## 5. Existing Pages to Update

### `index.html`
- Hero h1: "A new kind of partner for the people moving medicine forward" → **"BioMate is a computational biology assistant for every stage of biomedical science."** (user's directive: "BioMate is a computational biology assistant")
- Update "See how it works" button: currently links to `features.html` → link to `about.html#how-it-works`
- Add CTA bar before `<div id="bm-foot">`

### `features.html`
- Keep file accessible
- Update renderShell active slug from `'features'` to `'about'` (so About is highlighted when visiting it)
- Add CTA bar
- This page becomes accessible via About dropdown → "Platform Features"

### `about.html`
- Add CTA bar
- Update renderShell active to `'about'`

### `pricing.html`
- Add CTA bar

### `blog.html`
- Update page title/hero to say "Newsroom" 
- Update eyebrow from "From the BioMate team" to "Newsroom"
- Add CTA bar
- renderShell active changes from `'blog'` to `'newsroom'`

### All blog-*.html files
- Add CTA bar before `<div id="bm-foot">`

---

## 6. shell.js Changes

### navHTML()
- Replace `${link('features', 'Features', 'features.html')}` with dropdown:
  ```html
  <li class="bm-has-dropdown">
    <a href="services.html" class="...">Services ▾</a>
    <ul class="bm-dropdown">...</ul>
  </li>
  ```
- Add Newsroom dropdown (points to blog.html)
- Update About to dropdown
- Add Contact link
- Update Log in / Start free URLs to production (biomate.ai) if needed

### New CSS in shell (injected via `<style>` tag)
- `.bm-has-dropdown`: `position:relative`
- `.bm-dropdown`: absolute positioned, hidden by default, shown on hover/focus
- Mobile: dropdowns collapse into accordion under mobile toggle

### footerHTML()
- Product column: replace "Features" with "Platform" linking to `features.html`; add "Services" linking to `services.html`
- Company column: rename Blog → Newsroom; add Contact
- Science column: unchanged

### ctaHTML() (new function)
```javascript
function ctaHTML() {
  return `<section class="bm-cta-bar">...</section>`;
}
```

### renderShell()
- Accept optional `{ active, cta }` — if `cta !== false`, inject ctaHTML()
- `<div id="bm-cta"></div>` mount point in HTML, OR inject before footer

---

## 7. Styles Required (in shell or styles.css)

Dropdown styles — to be added to styles.css or injected by shell.js:

```css
.bm-has-dropdown { position: relative; }
.bm-dropdown {
  position: absolute; top: calc(100% + 8px); left: 0;
  background: var(--bg-card); border: 1px solid var(--border);
  border-radius: 10px; padding: .5rem 0; min-width: 220px;
  box-shadow: 0 8px 24px rgba(0,0,0,.1);
  opacity: 0; visibility: hidden; pointer-events: none;
  transform: translateY(-4px);
  transition: opacity .15s, transform .15s, visibility .15s;
  z-index: 200;
}
.bm-has-dropdown:hover .bm-dropdown,
.bm-has-dropdown:focus-within .bm-dropdown {
  opacity: 1; visibility: visible; pointer-events: auto;
  transform: translateY(0);
}
.bm-dropdown a {
  display: block; padding: .55rem 1.1rem;
  color: var(--ink); font-size: .92rem;
}
.bm-dropdown a:hover { background: var(--bg); color: var(--accent); }
```

CTA bar styles:
```css
.bm-cta-bar {
  background: var(--bg-ink); color: var(--on-ink);
  padding: 3rem 1rem; text-align: center;
}
.bm-cta-bar h2 { font-size: clamp(1.4rem, 3vw, 2rem); margin-bottom: .75rem; }
.bm-cta-bar-btns { display: flex; gap: .75rem; justify-content: center; flex-wrap: wrap; margin-top: 1.5rem; }
```

---

## 8. Implementation Order

1. Update `shell.js` — nav, dropdown JS, ctaHTML(), footerHTML() (all pages benefit immediately)
2. Update `styles.css` — add dropdown + CTA bar CSS
3. Create `services.html`
4. Create `contact.html`
5. Update `index.html` — hero h1, CTA bar, link fix
6. Update `blog.html` → Newsroom rename, CTA bar
7. Add CTA bar to `features.html`, `about.html`, `pricing.html`
8. Batch-add `<div id="bm-cta"></div>` + update renderShell active in all blog-*.html files

---

## 9. Out of Scope (This Session)

- Regulatory Compliance service page (needs 24–36 months of work first)
- Register page v2 redesign (separate task, lower priority)
- Payment/billing page (commented out per user instructions)
- Dashboard page (commented out per user instructions)
