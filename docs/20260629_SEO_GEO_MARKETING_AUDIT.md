# BioMate SEO, GEO & Marketing Audit — 2026-06-29

## Research Sources

- [GEO Best Practices 2026 — GenOptima](https://www.gen-optima.com/geo/generative-engine-optimization-best-practices-2026/)
- [GEO 2026 Full Guide — LLMrefs](https://llmrefs.com/generative-engine-optimization)
- [Mastering GEO in 2026 — Search Engine Land](https://searchengineland.com/mastering-generative-engine-optimization-in-2026-full-guide-469142)
- [llms.txt Best Practices 2026 — CrawlerOptic](https://www.crawleroptic.com/blog/llms-txt-best-practices)
- [llms.txt Complete Implementation Guide — Medium/Sourceable](https://medium.com/@besourceable/llms-txt-the-complete-implementation-guide-for-2026-34c8abac6576)
- [Entity SEO & Knowledge Graph Optimization 2026 — Digital Applied](https://www.digitalapplied.com/blog/entity-seo-knowledge-graph-optimization-guide-2026)
- [Schema Markup for SaaS 2026 — Rankeo](https://rankeo.io/blog/schema-markup-saas)
- [Structured Data for SEO 2026 — Digital Applied](https://www.digitalapplied.com/blog/structured-data-seo-2026-rich-results-guide)
- [Biotech Social Media Strategy 2026 — Samba Scientific](https://sambasci.com/blog/biotech-social-media-strategy/)
- [LinkedIn Marketing Strategy 2026 — LaGrowthMachine](https://lagrowthmachine.com/linkedin-marketing-strategy-2026/)
- [Biotech Marketing Strategy 2026 — MarketBeam](https://marketbeam.io/biotech-marketing-strategy-life-sciences/)
- [Pharma Marketing Strategy 2026 — Pharma Marketing Network](https://www.pharma-mkting.com/articles/pharma-marketing-strategy-2026/)
- [LinkedIn Thought Leader Ads for Biotech — Samba Scientific](https://sambasci.com/blog/the-biotech-marketers-guide-to-linkedin-thought-leader-ads/)

---

## Executive Summary

BioMate's public-facing assets have a strong technical foundation (robots.txt with AI crawlers, JSON-LD schema, FAQ schema, canonical URLs, llms.txt + llms-full.txt) but contain **critical inconsistencies** that directly undermine GEO performance. The headline number — workflow count — is 4,000+ on the homepage, 2,455+ in llms.txt, and 2,455 in CLAUDE.md. Every AI that reads llms.txt before answering "how many workflows does BioMate have?" will answer incorrectly. This is the single highest-priority fix.

Social media and marketing materials are strong in strategy (see `docs/20260509_marketing_positioning_strategy.md` and `docs/20260511_marketing_case_studies_current.md`) but have **zero executed content assets** — no post templates, no email outreach drafts, no LinkedIn article stubs.

---

## Part 1: GEO (Generative Engine Optimization) Audit

### What GEO Is (2026 Context)

GEO is the practice of structuring web content so AI-powered answer engines (ChatGPT, Perplexity, Google Gemini AI Mode, Microsoft Copilot, Claude) **cite, quote, or recommend** the content in generated answers. Gartner projects 25% decline in organic search traffic to commercial websites by 2026 as AI discovery replaces traditional search for many query types. The citation infrastructure matters as much as the content itself.

Key GEO metrics to track:
- **Mention Rate**: % of AI-generated answers that include "BioMate" by name across target prompts
- **Citation Rate**: % that include a clickable URL to biomate.ai
- **Position**: when cited, whether BioMate appears in the first mention vs. buried

### GEO Issues Found

#### CRITICAL — Workflow count mismatch across all LLM-readable surfaces

| Surface | States |
|---|---|
| `index.html` hero + stats | 4,000+ workflows, 36 domains |
| FAQ schema (`index.html` line 192) | 4,000+ (correct) |
| `llms.txt` (root GEO file) | **2,455+ workflows, 37 domains** |
| `llms-full.txt` (extended GEO file) | **2,455+ workflows, 37 domains** |
| `CLAUDE.md` (internal) | 2,455 workflows, 34 domains |

Every LLM that reads `llms.txt` (the primary GEO signal) will answer "BioMate has 2,455 workflows" while the homepage says 4,000+. Perplexity, ChatGPT with browsing, and Gemini all crawl llms.txt before HTML pages. **Status: Fixed in this session.**

#### HIGH — llms-full.txt domain counts are stale

`llms-full.txt` states `drug_discovery (61)` — the marketing strategy doc (2026-05-09) puts drug discovery at 160+. The per-domain stats in the extended file have not been updated since the initial DB import. These numbers are consumed verbatim by AI answer engines. **Status: Flagged for update; requires DB re-query.**

#### HIGH — No `llms-full.txt` alternate link in `<head>`

The `<head>` declares a link to `llms.txt` but not `llms-full.txt`. AI crawlers that auto-discover alternate representations via `<link rel="alternate">` will miss the extended index. **Status: Fixed in this session.**

#### MEDIUM — No freshness signal on llms.txt or llms-full.txt

Research shows 82% of Perplexity citations are content updated within 30 days (Q3 2025 data). Neither llms.txt nor llms-full.txt has a version date or `lastmod` declaration. Add a `## Last updated: YYYY-MM-DD` line to both files on every content update.

#### MEDIUM — Entity consistency: 34 vs. 36 vs. 37 domains

Domain count varies across sources (34 in CLAUDE.md, 36 on homepage, 37 in llms.txt). AI models that encounter conflicting entity facts about the same Wikidata Q-ID will reduce confidence and cite less often. Need a single canonical number. Align to homepage (36).

#### LOW — No `ai-plugin.json` / `openapi.json` at root

ChatGPT Plugin Store and Copilot plugin registry look for `https://domain/.well-known/ai-plugin.json`. BioMate already has an MCP connector and Open Claw API — publishing an OpenAPI schema here is low effort and opens ChatGPT plugin / Copilot integration channels.

#### LOW — Blog posts lack `<meta name="abstract">` or `<meta name="description">` per-article

LLMs summarize blog posts poorly without a citation-ready abstract. The blog architecture should add a per-article `<meta name="abstract">` pulled from the article's first paragraph. This is the most actionable blogging improvement for GEO citation.

### GEO Strengths (Do Not Change)

- `robots.txt` explicitly welcomes GPTBot, ClaudeBot, OAI-SearchBot, PerplexityBot, Bytespider, cohere-ai, meta-externalagent — excellent
- Wikidata entity Q140074014 is cited in llms.txt, llms-full.txt, and homepage FAQ — strong entity signal
- FAQPage JSON-LD on homepage directly maps to AI answer engine Q&A format — excellent
- `<link rel="alternate" type="text/plain" title="LLM-readable site index" href="https://biomate.ai/llms.txt" />` in head — correct

---

## Part 2: SEO Technical Audit

### Issues Found

#### HIGH — `og:image` uses logo instead of cover image

**Current:** `<meta property="og:image" content="https://biomate.ai/assets/logo.png" />`  
**Should be:** `https://biomate.ai/images/og-cover.png`

The `og-cover.png` file exists in `images/`. LinkedIn, X, Slack, and iMessage all render the `og:image` as a large preview card when someone shares the URL. A small square logo fills only a fraction of the card. The 1200×630 cover image is designed for this purpose. **Status: Fixed in this session.**

#### HIGH — Missing `twitter:image` meta tag

The Twitter card type is `summary_large_image` (which requires a 1200×628 image) but there is no `<meta name="twitter:image">` tag. Twitter/X falls back to `og:image` (the logo), but this fallback is unreliable. LinkedIn also uses `twitter:image` on some render paths. **Status: Fixed in this session.**

#### MEDIUM — Missing `og:image:width` and `og:image:height`

Without explicit dimensions, Facebook/LinkedIn crawl the image to detect size before rendering. This causes render delays and occasionally falls back to thumbnail mode. Standard cover is 1200×630. **Status: Fixed in this session.**

#### MEDIUM — Pricing mismatch: FAQ schema says "Enterprise at $199" but Offers schema says "Team at $199"

`FAQPage` answer (line 184): *"...Enterprise at $199/month (private VPC deployment, HIPAA BAA...)"*  
`SoftwareApplication.offers` (line 45–47): Team at $199  
`llms.txt`: Free / Pro $49 / Team $199 / Enterprise (contact sales)

The product has **four** tiers: Free / Pro $49 / Team $199 / Enterprise (custom). The FAQ collapsed Team + Enterprise into one "Enterprise $199" entry, which is wrong. Google's FAQ rich results and AI engines surface this pricing directly. **Status: Fixed in this session.**

#### LOW — Missing `twitter:site` handle

`twitter:site` enables X (Twitter) to attribute shares to the company's account. Not having it means X share cards show no brand attribution. **Action required: confirm @handle and add `<meta name="twitter:site" content="@biomate_ai" />`.**

#### LOW — Hero pill "Now in pilot" undermines conversion

"Now in pilot" signals beta / limited access. The product is live with a free tier. Recommended alternatives (choose one):
1. `Free for academic researchers` — highest-conversion for the primary ICP
2. `Now live — start free` — simple, removes uncertainty
3. `4,000+ workflows — start free` — product-led, factual

#### LOW — SoftwareApplication schema missing Enterprise offer

The `offers` array has Free / Pro / Team but no Enterprise entry. AI engines used for competitive research (e.g., "compare BioMate pricing to Schrödinger") will not surface Enterprise as an option. Add: `{"@type": "Offer", "name": "Enterprise", "description": "Custom pricing — private VPC, HIPAA BAA, SLA. Contact sales."}`.

### SEO Strengths (Do Not Change)

- Canonical URL declared
- FAQPage schema present — directly boosts Google FAQ rich results (35% higher CTR)
- SearchAction on WebSite schema enables Google sitelinks search box
- Google Analytics GA4 (G-65JDDPEDQ5) in place
- `<html lang="en">` — correct
- `sitemap.xml` referenced in robots.txt
- All four schema types needed for SaaS are present: WebSite, SoftwareApplication, Organization, FAQPage

---

## Part 3: Marketing Materials Audit

### Channel Assessment (2026 Data)

| Channel | Biotech Engagement | Priority |
|---|---|---|
| LinkedIn (personal profiles) | 2.60% engagement rate; 5.2× higher for scientific content | **Primary** |
| LinkedIn (company pages) | 1.74%; ~5% feed allocation | Supporting |
| X / Twitter | −14% biotech engagement since 2022 | Low |
| Bluesky / Threads | Growing for scientific discourse | Monitor |
| WeChat Work | Critical for Chinese pharma/academic market | High (BioMate already has connector) |

**Key 2026 algorithm fact:** LinkedIn's 2026 algorithm penalizes external links by 60% in feed distribution. Posts with external links (e.g., "Read our blog: link") get ~40% of the reach of native content. Strategy: post content natively on LinkedIn, put links only in comments.

### Marketing Gaps Found

#### GAP 1 — No social media content assets exist

The strategy docs are excellent research but produce zero publishable content. No templates, no calendar, no drafted posts. Every sales insight in `docs/20260511_marketing_case_studies_current.md` needs a 200-word LinkedIn post equivalent.

#### GAP 2 — No email outreach templates

Strategy (2026-05-09) names three outreach targets: (A) Series A/B biotechs in IND crunch, (B) Academic translation labs, (C) CRO channel partners. No draft emails exist.

#### GAP 3 — Benchmark scores not published on website

`llms.txt` references `benchmarks.html` with scores (94.6% routing accuracy, 100% PBPK validation, etc.) but these are not used in any social content, not cited in blog posts, and not cross-referenced in the FAQ schema. Benchmark scores are the single most credible social proof available to a technical buyer audience.

#### GAP 4 — Blog posts not promoted post-publication

The blog has 20+ articles covering high-value topics (GATK vs DeepVariant, ADMET guide, REINVENT4, CryoSPARC SPA). None appear to have associated LinkedIn posts, X threads, or email newsletter entries.

---

## Part 4: Action Plan

### Tier 1 — Implemented This Session (technical, no approval needed)

| Fix | File | Type |
|---|---|---|
| `og:image` → `og-cover.png` | `index.html` | SEO |
| Add `twitter:image` | `index.html` | SEO |
| Add `og:image:width/height` | `index.html` | SEO |
| Add `llms-full.txt` alternate link in `<head>` | `index.html` | GEO |
| Fix FAQ pricing: 3 plans → 4 plans, correct Team vs Enterprise | `index.html` | SEO + GEO |
| Add Enterprise to SoftwareApplication offers | `index.html` | SEO + GEO |
| Update workflow count 2,455+ → 4,000+ | `llms.txt` | GEO (critical) |
| Update domain count 37 → 36 | `llms.txt` | GEO |
| Update workflow count 2,455+ → 4,000+ | `llms-full.txt` | GEO (critical) |
| Update domain count 37 → 36 | `llms-full.txt` | GEO |

### Tier 2 — Needs Decision / Content Approval

| Action | Owner | Priority |
|---|---|---|
| Change hero pill from "Now in pilot" → chosen alternative | Founder | HIGH |
| Add `twitter:site` with confirmed @handle | Founder | LOW |
| Add last-updated date to llms.txt and llms-full.txt (quarterly cadence) | Eng | MEDIUM |
| Correct per-domain workflow counts in llms-full.txt (DB re-query) | Eng | HIGH |
| Add `ai-plugin.json` at root exposing BioMate MCP/OpenAPI | Eng | MEDIUM |
| Add `<meta name="abstract">` to all blog post `<head>` tags | Eng | MEDIUM |

### Tier 3 — Marketing Content (To Be Created)

#### LinkedIn Post Templates Needed (5 personas)

1. **Bench scientist** — "I uploaded my count matrix and got DESeq2 results in 8 minutes" angle
2. **Pharma CSO** — FAP CAR-T / Talquetamab case study angle (from strategy doc)
3. **Biotech at IND crunch** — "6 months from IND, no SimCYP license" angle
4. **Academic PI** — "Free for non-profits, full Bioconductor library" angle
5. **CRO partner** — "AI-augmented ADMET/PBPK as a service" angle

#### Email Outreach Templates Needed (3 sequences)

1. **Series A/B IND crunch** — subject: "You're 6 months from IND. Here's how to compress 3 months of CRO work into 2 weeks."
2. **Academic translation lab** — subject: "Full ADMET + PBPK stack, free for your lab"
3. **CRO channel partner** — subject: "Your clients want computational ADMET. We power it, you deliver it."

#### Benchmark-led Content Needed

- LinkedIn post: "We ran 5 drug design queries through GPT-5.5, Gemini, Claude, and BioMate. Only BioMate ran pipelines." (hook from `blog-llm-comparison.html`)
- Twitter/X thread: "Atlas-driven modality triage — what BioMate would have predicted about 7 FDA approvals from Q4 2024" (from case studies doc)

---

## Part 5: GEO Content Quality Standards (Apply Going Forward)

Based on 2026 research:

1. **Definitional first sentence** — every page should answer "what is X" in the opening line. CMU research shows pages with clear definitional structure in the first 150-200 tokens receive significantly higher AI impression scores.

2. **Freshness cycle** — update llms.txt, llms-full.txt, and key landing pages every 7–14 days. 82% of Perplexity citations are from content updated within 30 days.

3. **FAQ blocks above the fold** — FAQPage schema maps directly to AI Overview answer format. The homepage FAQ schema is strong but should also appear as visible HTML content (not just JSON-LD) for AI crawlers that parse the rendered DOM.

4. **Specific, citable numbers** — "94.6% first-pick routing accuracy" beats "highly accurate routing" for AI citation. The benchmark page is critical GEO infrastructure; link to it from more pages.

5. **Entity consistency** — the same facts (founding year, headquarters, Wikidata Q-ID, workflow count, pricing) must be identical across every page, llms.txt, llms-full.txt, and JSON-LD. Contradictions reduce citation confidence.

6. **Wikidata enrichment** — Wikidata Q140074014 is cited on the site. Verify the entity has: founder names, founding date (2025), headquarters (Houston TX → TMC), website URL, description, and product/service category. A well-populated entity strengthens Knowledge Graph recognition across Google, Bing, and AI engines.
