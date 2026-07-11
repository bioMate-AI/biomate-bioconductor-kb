# SEO, GEO & Compare Page Updates — 2026-07-04

## Context

Continuation of the compare page work from 2026-07-03. Applied the SEO/GEO audit
standards from `docs/20260629_SEO_GEO_MARKETING_AUDIT.md` to all pages touched
in the prior session: compare.html, features.html, and three recent blog posts.

---

## Changes Made

### 1. compare.html — LABBench citation fix

**Problem:** Benchmark section attributed LABBench to "FutureHouse, 2025."
FutureHouse also built Robin + Finch. Saying "proposed by FutureHouse" while
explaining their own system has no score on it looked contradictory.

**Fix:** Changed attribution from "FutureHouse, 2025" → "Jansen et al., 2025"
(the paper authors), which cleanly separates the researchers who published the
benchmark from the organization's Robin + Finch product. Description now reads:
"The original paper reports evaluation results for foundation LLM baselines;
BioMate's score reflects BioMate's own evaluation run against the published
LABBench dataset (April 2026)."

### 2. compare.html — Full SEO + GEO treatment (was missing everything)

Added:
- `<link rel="canonical" href="https://biomate.ai/compare.html" />`
- `<link rel="alternate" type="text/plain" href="https://biomate.ai/llms.txt" />`
- Full Open Graph block: `og:type=article`, title, description, url,
  `og:image=images/og-cover.png` (1200×630), `og:image:width/height`,
  `og:site_name`, `article:published_time=2026-07-03`
- Twitter card block: card type, title, description, `twitter:image`
- `<meta name="abstract">` — specific, citable one-paragraph summary with
  benchmark scores (the primary GEO signal for AI answer engines)
- **3 JSON-LD blocks:**
  - `BreadcrumbList`: Home › Company › BioMate vs. The Alternatives
  - `Article`: headline, description, datePublished, author, publisher,
    mainEntityOfPage, image
  - `FAQPage` (6 Q&As): How does BioMate compare to Claude Science?; Which
    platform leads BixBench?; What is BiomniEval1?; Can GPT-5.5 run pipelines?;
    What databases does BioMate query?; How does BioMate score on LABBench?

### 3. features.html — SEO fixes

Per audit (June 29), three HIGH/MEDIUM issues fixed:
- `og:image`: `assets/logo.png` → `images/og-cover.png` (1200×630 cover)
- `og:image:width` / `og:image:height` added (prevents LinkedIn/Facebook
  fallback to thumbnail mode)
- `twitter:image` added (was missing despite `summary_large_image` card type)
- New FAQPage entry: "What biological databases does BioMate AI access?" —
  covers all 6 database groups including the data sources section added Jul 3

### 4. blog-databases.html (Jul 3) — SEO/GEO additions

- `meta name="abstract"`: 60+ live databases summary, worked examples mention
- `og:image:width/height`: 1200×630
- `article:published_time`: 2026-07-03
- `llms.txt` alternate link
- **New FAQPage JSON-LD** (was missing entirely): 3 Q&As covering
  which databases BioMate connects to, live vs. cached, and PubMed integration

### 5. blog-why-ai-bioconductor-doesnt-run.html (Jun 30) — SEO/GEO additions

- `meta name="abstract"`: 71.4% → 88.2% accuracy, execution grounding thesis
- `og:image:width/height`: 1200×630
- `article:published_time`: 2026-06-09
- `llms.txt` alternate link
- FAQPage was already present — no change needed

### 6. blog-agent-skills-vs-biomate.html (Jun 30) — SEO/GEO additions

- `meta name="abstract"`: skills improved in 2026; CI validates doc not code;
  execution is the line
- `og:image:width/height`: 1200×630
- `article:published_time`: 2026-06-29
- `llms.txt` alternate link
- FAQPage was already present — no change needed

### 7. llms.txt + llms-full.txt — freshness signal

Added `## Last updated: 2026-07-03` to both files. Per audit: 82% of Perplexity
citations go to content updated within 30 days. This line should be updated on
every content push going forward.

---

## Deployment

All changes deployed via `scripts/deploy_marketing.sh` to `biomate.ai` (52.42.49.175).
nginx reloaded successfully each deploy. No errors.

---

## GEO Signal Summary — Why `meta name="abstract"` Matters

Per the June 29 audit, CMU research shows pages with clear definitional structure
in the first 150-200 tokens receive significantly higher AI impression scores.
The `abstract` meta tag gives Perplexity, ChatGPT (browsing), and Gemini a
dense, pre-parsed summary to quote directly in generated answers — without having
to parse the full article body. Every page that can be cited in an AI answer
should have one. Standard added to all new blog posts going forward.

---

## Open Issues / Next Steps

1. **Head-to-head comparison table** in compare.html is still commented out —
   needs detailed revision before publishing (left as-is by design).

2. **BioMate execution benchmarks blog** — user suggested a separate blog
   emphasizing ADMET, PBPK, IND execution benchmarks "from the product point of
   view, since other tools have not evaluated from that angle." Not yet created.

3. **llms-full.txt per-domain counts** — still showing stale numbers
   (`drug_discovery (61)` while marketing puts it at 160+). Requires DB
   re-query to get current per-domain counts. Flagged in June 29 audit.

4. **`twitter:site` handle** — still missing across all pages. Needs confirmed
   @handle from founder before adding.

5. **Older blog posts** (Jun 16 and earlier) — not touched this session.
   Apply the same SEO/GEO treatment (abstract, og dimensions, llms.txt link)
   as a batch task.
