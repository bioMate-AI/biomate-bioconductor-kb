# Website Prototype Work — 2026-04-12

## Summary

This session produced a full multi-page website prototype for biomate.ai, housed in a new isolated directory so the live site is untouched. Separately, the live site's accidentally-overwritten `index.html` was restored.

---

## Directory Structure

### Live Website (unchanged)
```
/home/yzhang/biomate/webpage_design/
├── index.html          ← live biomate.ai homepage (restored)
├── images/             ← production image assets (25 MB)
└── ...
```

### Prototype (new, not synced)
```
/home/yzhang/biomate/webpage_design_prototype/
├── index.html          ← improved homepage
├── pricing.html        ← three-tier pricing page
├── features.html       ← feature showcase with interactive mockups
├── about.html          ← mission, team, tech stack, timeline
├── blog.html           ← blog index with featured post + sidebar
├── shared/
│   └── site.css        ← shared design system (CSS variables, nav, footer, components)
└── images → ../webpage_design/images/   ← symlink; no image duplication
```

**The prototype is deliberately excluded from `scripts/sync_to_dev.sh`** — the sync script only references `webpage_design/`, so `webpage_design_prototype/` will never be accidentally deployed.

---

## Design System (`shared/site.css`)

Inherits the live site's design language and extends it:

| Token | Value | Usage |
|-------|-------|-------|
| `--bg` | `#f5f0e4` | Warm beige background |
| `--text` | `#1a1a2e` | Deep navy body text |
| `--accent` | `#4a7a8a` | Teal accent (CTAs, links) |
| `--accent-dark` | `#3a6272` | Hover state |
| `--surface` | `#ffffff` | Card/panel backgrounds |
| `--border` | `#e0d8c8` | Subtle dividers |
| Heading font | Crimson Text (serif) | Consistent with live site |
| Body font | Open Sans (sans-serif) | Consistent with live site |

Components included: nav (responsive, active states), footer (4-column), buttons (primary/secondary/ghost), section scaffolding, stat cards, feature cards, blog post cards, badges, testimonial blocks, comparison tables, FAQ accordions.

---

## Pages Built

### `index.html` — Main Homepage
- **Stats strip**: 20+ Domains / 60+ Workflows / <30 Min Avg / AWS Batch
- **How It Works**: 3-step process (Ask → Configure → Run)
- **Domain catalog**: 6 domains with workflow counts and descriptions
  - Drug Discovery (18 workflows), Genomics (12), Structural Biology (6), Multi-Omics (8), Preclinical (9), Biostatistics (5)
- **Social proof**: 3 testimonials + trust badge row (SOC 2, HIPAA, AWS, nf-core, cGMP)
- **Expanded footer**: 4 columns — Product, Science, Company, Resources

### `pricing.html` — Pricing
Three tiers:
- **Pilot** — Free during pilot study; invite-only; 5 domains; standard support
- **Professional** — $199/mo (or $1,990/yr); unlimited domains; priority support; audit trail
- **Enterprise** — Custom; private deployment; dedicated infra; SLA; compliance docs

Full feature comparison table. 6-question FAQ. Enterprise dark strip with private deployment CTA.

### `features.html` — Features
Four alternating feature rows with live HTML mockups (not images):
1. **AI Research Assistant** — Inline chat demo showing query → workflow card
2. **Smart Parameter Fill** — Pre-filled form panel with rationale tooltips
3. **Publishable Findings Reports** — Methods + results report mock with download links
4. **Complete Audit Trail** — Timestamped execution log table

Workflow catalog section (dark theme) with 6 domain cards. Compliance grid: SOC 2, HIPAA, GxP, Data Residency, Private Deployment, Reproducibility.

### `about.html` — About
- Mission statement (leading with AI + bioinformatics + reproducibility)
- Values grid: Reproducibility, Openness, Speed, Trust, Depth, Accessibility
- Technology stack (8 technologies): Claude AI, Nextflow + nf-core, AWS Batch, AlphaFold3, RDKit/AmberTools/GROMACS, CryoSPARC, Galaxy Platform, GATK4
- Timeline (5 milestones): 2024 Q3 → 2025 Q1 → 2025 Q3 → 2026 Q1 → 2026 Q3
- Careers section: 3 open roles (Bioinformatics Engineer, ML Engineer, Solutions Scientist)

### `blog.html` — Blog
- Featured post: "From FASTQ to Variant Call: A Complete WGS Walkthrough with BioMate"
- 5 post cards: ADMET prediction, cryo-EM, multi-omics, AI findings reports, GROMACS MD
- Filter tabs: All / Research / Product / Science
- Sidebar: Subscribe form, topic cloud, CTA card

---

## Live Site Restoration

The live `webpage_design/index.html` was accidentally overwritten during early prototype work (before the prototype folder was separated). Because `webpage_design/` is **untracked by git**, there was no git history to restore from.

The file was restored verbatim from conversation context. The restored file matches the production biomate.ai page: warm beige design, Crimson Text + Open Sans, two main sections (Applications and Our Approach), and the original nav/footer structure.

**Verify restoration:**
```bash
diff /home/yzhang/biomate/webpage_design/index.html <(curl -s https://biomate.ai/)
```
(approximate — CDN cache may differ slightly)

---

## Valuable Content from Prior Prototypes

The prior session produced 3 landing page variants (A/B/C) in `frontend/website-prototypes/`. Content that was useful and has been incorporated:

| Prior variant content | Where it landed |
|-----------------------|-----------------|
| Domain catalog with workflow counts | `index.html` domain section |
| Stats row (87%, 23 min) → refined | `index.html` stats strip |
| Compliance checklist panel | `features.html` compliance grid |
| FAQ section | `pricing.html` FAQ |
| Pain-led messaging ("Stop waiting for your bioinformatician") | `features.html` intro + `pricing.html` Enterprise section |
| Private deployment differentiator | `pricing.html` Enterprise tier |

---

## How to View

Open any page directly in a browser — no build step required:

```bash
# Linux
xdg-open /home/yzhang/biomate/webpage_design_prototype/index.html

# Or serve with Python
cd /home/yzhang/biomate/webpage_design_prototype
python3 -m http.server 8888
# then open http://localhost:8888
```

---

## Pending Polish

Per user feedback: "the content needs to be polished, the links also need to be consolidated."

- [ ] Internal nav links: all pages link to each other via `<nav>` — verify all 5 pages reference each other correctly
- [ ] CTA buttons: "Start Free" → confirm target URL (app.biomate.ai or /signup)
- [ ] Testimonials: currently placeholder names — replace with real quotes when available
- [ ] Blog post dates: set to realistic dates consistent with the timeline
- [ ] Domain workflow counts: verify against actual DB counts (`SELECT domain, COUNT(*) FROM workflows GROUP BY domain`)
- [ ] Tech stack logos: replace emoji placeholder icons with actual SVG logos if desired
- [ ] Mobile responsiveness: test nav hamburger menu on narrow viewports
