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
- ~~Team~~ *(commented out for now)*

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
Stats bar: 2,000+ workflows · 20+ biomedical domains · Evidence-graded QC on every result

---

#### Service 1 — Drug Discovery
Sub-categories (each is a named card with tools + outputs):

| Sub-category | Key tools/pipelines | Outputs |
|---|---|---|
| **Target Discovery** | CRISPR essentiality, functional genomics, pocket druggability scoring, genetic support scoring | Ranked target list, druggability report |
| **Virtual Screening & Hit Discovery** | AutoDock Vina, DiffDock, pharmacophore filtering, fragment-based screening | Top-scored hits, pose clusters, binding affinity table |
| **ADMET & Lead Optimization** | Full ADMET panel (hERG, DILI, Ames, Ro5), CYP450 DDI, GROMACS MD, REINVENT4 generative design | ADMET report, Gold/Silver/Bronze QC grade, redesigned scaffold suggestions |
| **Preclinical Development** | PBPK simulation, allometric scaling, toxicity prediction, CRO package assembly | PK profiles, species scaling tables, CRO submission package |
| **Clinical Pharmacology** | PopPK modeling, dose-escalation simulation, pharmacogenomics, drug-drug interaction | PK/PD projections, MTD estimate, DDI risk report |
| **Pharmacovigilance** | Post-market signal detection, adverse event analysis, disproportionality scoring | Signal detection report, FAERS analysis |

---

#### Service 2 — Genomics & Multi-Omics
Sub-categories (DB: transcriptomics 865 workflows, genomics 369, epigenomics 133, proteomics 113):

| Sub-category | Key tools/pipelines | Outputs |
|---|---|---|
| **Whole Genome & Exome Sequencing** | nf-core/sarek, GATK Best Practices, DeepVariant, Strelka2 | Annotated VCF, ACMG-classified variants, QC report |
| **Transcriptomics** | nf-core/rnaseq (bulk), nf-core/scrnaseq (10x), differential expression, pathway enrichment | DEG tables, volcano plots, GSEA, cell-type annotations |
| **Epigenomics** | nf-core/atacseq, nf-core/chipseq, nf-core/cutandrun, bisulfite methylation | Peak calls, differential accessibility, motif enrichment, DMR maps |
| **Proteomics** | DIA-NN, nf-core/proteomicslfq (LFQ), TMT multiplexing, PTM analysis | Protein quantification tables, differential abundance, pathway maps |
| **Metabolomics** | Untargeted/targeted metabolomics, XCMS, pathway enrichment | Feature tables, metabolite IDs, enriched pathways |
| **Metagenomics** | Shotgun metagenomics, 16S rRNA (QIIME2), taxonomic profiling, functional annotation | Taxonomic composition, alpha/beta diversity, functional profiles |
| **Multi-Omics Integration** | MOFA+, iCluster, cross-omics correlation, integrative pathway analysis | Multi-omics factor loadings, integrated pathway report |

---

#### Service 3 — Structural Biology
Sub-categories (DB: cryo_em 10+ workflows, protein_structure domain):

| Sub-category | Key tools/pipelines | Outputs |
|---|---|---|
| **Cryo-EM Single Particle Analysis** | CryoSPARC SPA (full pipeline: import → CTF → picking → 2D/3D → refinement → validation) | Refined density map (near-atomic resolution), FSC curves, EMDB-ready package |
| **Protein Structure Prediction** | AlphaFold3 (monomer & multimer), ESMFold, structure validation (MolProbity) | PDB structure file, pLDDT/PAE plots, Ramachandran report |
| **Molecular Dynamics** | GROMACS, AmberTools, protein-ligand MD, free energy perturbation (FEP) | Trajectory files, RMSD/RMSF plots, binding free energy (ΔG) |
| **Molecular Docking** | AutoDock Vina, DiffDock, Glide (via REINVENT4), binding pose clustering | Top-ranked poses, binding affinity scores, interaction fingerprint |

---

#### Cross-service capabilities (shown at bottom of services.html)
- Audit trail on every run (timestamped, exportable)
- Evidence-graded QC — Gold (FDA/ICH consensus), Silver (community standard), Bronze (field heuristic) — with cited source for each threshold
- AI-generated Methods section ready to paste into a regulatory filing or paper
- GPU-backed cloud execution — minutes, not days
- 2,000+ validated workflows across 20+ biomedical domains

#### IND Nonclinical Package (cross-service feature, shown prominently)
BioMate covers ~60–70% of the in silico sections of IND Module 2.6 today:

| IND Section | Status |
|---|---|
| §2.6.1 Introduction | ✅ Already built (LLM narrative, download endpoint live) |
| §2.6.2 Pharmacology summary | ✅ From docking + target discovery + hERG |
| §2.6.3 Pharmacology tables | ✅ From ADMET panel |
| §2.6.4 PK written summary | ✅ From PBPK + NCA-PK + ADME |
| §2.6.5 PK tables | ✅ From PK runs |
| §2.6.6 Toxicology summary | ~Partial (Ames, DILI, hERG; missing in vivo) |
| §2.6.7 Toxicology tables | ~Partial |

**Positioning**: "IND Nonclinical Package — the in silico sections of §2.6.1–2.6.7, CTD-formatted, audit-ready, structured for your RA team."
Wet-lab sections remain as placeholders. BioMate does not overclaim.
Roadmap: §2.6.6 tox expansion (6 mo) → Veeva Vault API push (12–18 mo).

Add to services.html: "IND Nonclinical Package" as named output under Drug Discovery → Preclinical Development.
Add to cross-service capabilities bar: "IND §2.6 nonclinical package — computational sections, CTD-formatted, audit-ready"

NOT included: Regulatory Compliance as a standalone service (per gap analysis — 24–36 month roadmap, $1.1–1.9M investment)

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
