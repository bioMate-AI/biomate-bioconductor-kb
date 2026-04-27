# BioMate AI — Design Brief

## What is BioMate?

BioMate is an AI-powered computational platform for any team doing demanding biomedical work — pharma, biotech, CROs, CDMOs, clinical, regulatory, and academic core facilities. Users describe a scientific objective in plain language; BioMate selects the right validated workflow, runs it on cloud compute, and returns QC-graded, audit-ready results in minutes.

**Not** a drug discovery tool only. **Not** a research-only tool. The platform covers 20+ biomedical domains: genomics, transcriptomics, proteomics, metabolomics, structural biology (cryo-EM, docking, MD), drug discovery (ADMET, PBPK, generative design), clinical pharmacology, pharmacovigilance, epigenomics, single-cell, and more.

**Scale**: 2,000+ validated workflows, 20+ domains, cloud-native GPU execution.

---

## Brand Identity

| Element | Value |
|---------|-------|
| Background | `#f5f0e4` (warm parchment) |
| Card background | `#ece7d8` |
| Accent | `#4a7a8a` (teal-blue) |
| Accent light | `#3a6878` |
| Body text | `#1c2b32` |
| Muted text | `#5a7280` |
| Border | `#cec5ae` |
| Heading font | Crimson Text (serif) — loaded from local TTF |
| Body font | Open Sans — loaded from local TTF |
| Radius | 10px |

**Tone**: Scientific authority without jargon. Business outcomes for decision-makers. Confident, precise, not breathless.

**Target audience**: C-suite and VP-level executives at pharma, biotech, CROs — people who care about speed, cost, risk reduction, and regulatory confidence, not pipeline names or tool choices.

---

## Website Structure

All files are in this folder. Self-contained — local fonts (`fonts/fonts.css`), local images (`images/`), no CDN.

| Page | File | Purpose |
|------|------|---------|
| Home | `index.html` | Hero + how it works + applications + approach + social proof + CTA |
| About | `about.html` | Company story, values, team, vision |
| Features | `features.html` | Product capability deep-dive |
| Pricing | `pricing.html` | Plans and tiers |
| Blog | `blog.html` | Blog listing (featured post + 19 cards + sidebar) |
| Blog articles | `blog-*.html` | 19 individual posts |

---

## Current State & What Has Been Done

### Completed
- Full SEO/GEO: canonical tags, Open Graph, Twitter Cards, JSON-LD structured data on all pages
- `sitemap.xml` and `robots.txt` at root
- All blog article images replaced with AI-generated photorealistic hero images
- All sidebar links in blog.html wired to real pages (drug discovery series, topic chips, subscribe)
- "Houston, Texas" removed everywhere
- "60+" → "2,000+" everywhere
- AWS Batch, nf-core, Nextflow removed from user-visible copy
- About page rewritten for C-suite audience — business outcomes, not technical capabilities
- Index hero: simplified badge + punchy subtitle
- Index all sections: cut to one tight sentence per card, benefit-first headings

### Design Decisions Made
- Technical detail lives in SEO metadata (keywords, JSON-LD featureList), not in visible copy
- Visible copy = powerful + concise + benefit-oriented
- No domain or tool lock-in in main narrative (BioMate is not "just drug discovery" or "just research")

---

## Areas Requesting Design Review

### 1. Overall visual impression
Does the warm parchment palette (`#f5f0e4`) feel appropriate for a premium B2B SaaS targeting pharma executives? Is there enough visual hierarchy? Does it feel trustworthy and modern?

### 2. Hero section (`index.html`)
- Current: "A virtual lab / that thinks" with a dark-overlay background photo
- Is the headline strong enough for a C-suite audience?
- Is the CTA button hierarchy (primary blue + ghost white) clear?

### 3. Stats bar
Current stats: "20+ Research Domains", "2,000+ Validated Workflows", "<30 min Average Time to Results", "Gold / Silver / Bronze Evidence-Graded QC"
- The last stat is verbose — suggestions welcome for how to communicate QC tiering in a stat format

### 4. Applications section
Six cards, each with a 16:9 image + category tag + h4 title + one sentence.
- Are the images (domain illustrations) working visually?
- Is the card grid scannable at a glance for an executive who doesn't read every word?

### 5. Approach section
Six cards: Data Foundation, Intelligent Routing, No-Code Execution, Audit-Ready Results, Community Standards, Elastic Cloud Compute
- These are fairly abstract principles. Would benefit icons work better than images here?

### 6. Social proof
Three testimonial cards with quotes from fictional early users.
- Once real testimonials are available, what format works best (headshot + name + company vs. current author/role only)?

### 7. Blog page (`blog.html`)
- Featured post takes full width at top; below is a 2-column grid of cards + right sidebar
- Sidebar has: Drug Discovery series links, topic chips, and subscribe form
- All links are now wired. Does the sidebar feel useful or cluttered?

### 8. Typography scale
- Crimson Text for all headings (h1–h4) — does the serif feel premium or dated?
- Open Sans for body — neutral and legible, but fairly generic

### 9. Navigation
Currently: How It Works · Applications · Our Approach · Pricing · About · Blog · Contact | Log In · Get Started
- Is this too many items? Would a simpler nav (Product · Pricing · Blog · About + CTA) feel cleaner?

### 10. Mobile responsiveness
- Nav collapses fully on mobile (hidden below 720px) — no hamburger menu
- Cards go single-column
- Is the mobile experience acceptable or does a hamburger menu need to be added?

---

## Specific Requests

1. **Critique the hero**: Is "A virtual lab that thinks" the right headline for this audience? Alternatives?
2. **Approach section**: Should these be icon cards instead of image cards? The images feel generic here.
3. **Blog hero images**: All AI-generated photorealistic images. Review `images/blog-*-hero.png` — do they feel cohesive? Are any obviously wrong?
4. **Color palette**: Is there a case for a darker, more enterprise-feeling variant? Or does the warmth differentiate positively?
5. **CTA copy**: Current — "Bring your question. BioMate handles the rest." — feedback welcome.
6. **Any layout, spacing, or component suggestions** you'd make for a platform targeting pharma decision-makers.

---

## Files of Interest

```
webpage_design_new/
├── index.html          ← Home page (start here)
├── about.html          ← About page
├── blog.html           ← Blog listing
├── blog-*.html         ← 19 blog article pages
├── features.html
├── pricing.html
├── images/             ← All images (logos, heroes, domain art, blog heroes)
│   ├── logo.png
│   ├── og-cover.png    ← Social sharing image
│   ├── blog-*-hero.png ← 19 blog hero images
│   └── 2026-04-08-*   ← Domain and approach card images
├── fonts/
│   └── fonts.css       ← Local font declarations
├── sitemap.xml
└── robots.txt
```

---

*Document prepared 2026-04-24. For questions, contact the BioMate engineering team.*
