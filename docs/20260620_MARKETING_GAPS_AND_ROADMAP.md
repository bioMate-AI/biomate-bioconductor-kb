# BioMate AI — Marketing Gaps & Roadmap
**Date:** 2026-06-20  
**Status:** Planning

---

## What Already Exists

| Asset | Location | Notes |
|---|---|---|
| Full website (35+ pages) | `webpage_design_v2/` | Homepage, features, blog, pricing, compare, domain product pages |
| 35+ blog posts | `webpage_design_v2/blog-*.html` | Drug discovery series, technical guides, deep dives |
| 39 LinkedIn/Substack posts | `business/marketing/blog_posts/` | Dual-format, editorial calendar in place |
| Video presentation | `reference/claude_design/biomate-intro-v3/` | English + Chinese, with voice-over, 53MB MP4 |
| Social media launch content | `business/marketing/public_channels/` | Twitter, Reddit, nf-core Slack, GitHub setup |
| Prospect lists | `business/marketing/targets/` | Texas, CRO labs, DOE labs, Gulf Coast, ag-genomics (~200+ prospects) |
| Outreach email automation | `business/marketing/outreach_agent.py` | Templated email campaigns |
| CRO compliance page | `reference/claude_design/cro/` | Product marketing for CRO workflows |
| IND report showcase | `reference/claude_design/ind_design/` | FDA submission reporting feature |
| SEO audit | `business/marketing/BioMate Full Site Audit-May 31 2026.pdf` | Website SEO/UX audit |
| Quickstart guides | `reference/claude_design/biomate/` | English + Chinese multilingual |
| Wikipedia draft | `docs/20260618_WIKIPEDIA_DRAFT_BIOMATE_V2.md` | V2 ready, pending independent press coverage before submission |
| Platform architecture diagram | `webpage_design_v2/assets/platform-diagram.svg` | Added to index.html June 2026 |

---

## Gaps — Marketing Materials to Build

### Priority 1 — High Impact, Short Timeline

#### 1. Press Kit (`/press.html`)
A dedicated page for journalists, conference organizers, and investors.

**Contents:**
- One-paragraph boilerplate (English + Chinese)
- Key facts: founded, HQ, team size, funding stage, workflow count, routing accuracy, benchmark scores
- Logo pack download (SVG, PNG, light/dark variants)
- Product screenshots ZIP
- Founder headshot and bio
- Media contact: `press@biomate.ai`
- Recent coverage (if any) or "available for interview" invite
- Analyst/research citations (VirBench, Robin, Nature editorial)

**Why now:** Any conference appearance, press mention, or investor conversation needs a press page link. Currently none exists.

---

#### 2. Case Studies (`/case-studies.html` + individual pages)
Structured before/after stories using real workflow examples.

**Suggested case study templates:**
- **RNA-seq in 2 hours** — Lab uploads FASTQ files → BioMate routes to nf-core/rnaseq → auto-QC → DESeq2 results + Methods section in one session
- **ADMET screening loop** — 12 compounds → ADMET workflow → QC gate fires on hERG → auto-remediation → 8 compounds pass → CRO submission package
- **CryoEM reconstruction** — MRC files → CryoSPARC SPA → 3D reconstruction → RELION refinement → PDB-ready output
- **Variant calling (WGS)** — 30× WGS BAM → GATK4 + DeepVariant → VCF with pathogenicity annotation → clinical report

**Structure per case study:**
- Problem (what the lab was doing before)
- Solution (what BioMate workflow they ran)
- Result (time saved, accuracy, output artifacts)
- Quote (if real customer) or representative narrative
- CTA: "Run this workflow →"

---

#### 3. Email Drip Sequence (onboarding)
A structured email campaign triggered on registration.

**Sequence (7 emails):**
| Day | Subject | Content |
|---|---|---|
| 0 (signup) | "Your 50 free credits are ready" | Welcome, link to quickstart, what to run first |
| 1 | "Run your first workflow in 5 minutes" | Walk through one RNA-seq or ADMET example |
| 3 | "What 4,000+ workflows actually means" | Domain coverage, Bioconductor depth, GPU pipelines |
| 7 | "Your first week with BioMate" | Usage summary, suggest next workflow |
| 14 | "Your free credits expiry reminder" | Prompt to purchase credits or upgrade |
| 21 | "How researchers use BioMate for publication-ready results" | Link to case study / blog post |
| 30 | "Upgrade to Premium — here's what you unlock" | Feature comparison, academic discount reminder |

**Files to create:** `business/marketing/email_drip/` — one markdown file per email with subject, body, CTA, and send conditions.

---

### Priority 2 — Medium Impact, Medium Timeline

#### 4. Conference / Event Materials

**For ASHG, ISMB, AACR, ACS, SLAS:**
- **Poster template** (A0 portrait): BioMate platform diagram + benchmark results + QR code to biomate.ai
- **Abstract template**: 250-word template that researchers can adapt for their own BioMate-assisted analysis
- **Booth one-pager**: Single A4/Letter page with hero value prop, feature bullets, pricing CTA, and QR code
- **Talk slide deck template**: 15-slide deck (problem → solution → demo → results → pricing)

**File location:** `business/marketing/conference/`

---

#### 5. ROI / Time-Savings Calculator (`/roi-calculator.html`)
An interactive page that lets researchers estimate how much time and money BioMate saves.

**Inputs:**
- How many workflows per month? (slider)
- Average manual setup time per workflow? (dropdown: 2h / 4h / 8h)
- Hourly rate or stipend (optional)
- Workflow types (RNA-seq, variant calling, drug design, cryo-EM)

**Outputs:**
- Hours saved per month
- Estimated cost of manual analysis vs. BioMate credits
- "Break-even vs. Premium" calculation
- "How much would this cost on cloud compute alone?"

---

#### 6. Testimonials / Social Proof Page (`/testimonials.html`)
A structured page for quotes, case excerpts, and social signals.

**Sections:**
- Researcher quotes (name, institution, workflow used)
- Star ratings by category (ease of use, accuracy, output quality)
- Usage stats ("X runs completed", "Y papers acknowledged BioMate")
- Integration logos (Illumina, Benchling, Slack, Oxford Nanopore)

**Template for quote collection:** `business/marketing/templates/testimonial_request.md`

---

#### 7. One-Pager PDF (Sales Leave-Behind)
A single-page PDF for sales meetings and conference booths.

**Contents:**
- Hero: "Agentic AI for Biomedicine"
- Platform diagram (from `platform-diagram.svg`)
- 4-column feature grid (AI routing, 4,000+ workflows, QC grading, audit trail)
- Pricing: Free credits → Pay-as-you-go → Team
- Benchmark callout: 94.6% routing accuracy, VirBench citation
- Contact + QR code

**Format:** HTML-to-PDF (printable version of a landing page), saved as `business/marketing/collateral/biomate_one_pager.pdf`

---

### Priority 3 — Lower Urgency

#### 8. Comparison Sheet (PDF download)
A downloadable PDF version of `compare.html` — BioMate vs. Galaxy, Terra, DNAnexus, Benchling, Schrödinger, Benchling.

#### 9. Partner / Integration Co-Marketing
One-pager for each key integration:
- BioMate × Illumina BaseSpace
- BioMate × Oxford Nanopore
- BioMate × Benchling LIMS
- BioMate × Slack

#### 10. Investor / Pitch Deck
15–20 slides: problem, solution, market size, traction, team, ask. Currently only the HTML presentation exists; no investor-specific deck.

---

## Suggested Build Order

```
Week 1:  Press kit page + 50-credit free tier on pricing
Week 2:  Email drip sequence (7 emails)
Week 3:  Case studies page + 2 case study write-ups
Week 4:  ROI calculator
Month 2: Conference materials + testimonials page + one-pager PDF
Month 3: Comparison PDF + partner pages + investor deck
```

---

## Notes

- Wikipedia draft is ready but needs independent press coverage first — push PR to biomedical AI journalists to unblock this.
- The `llms.txt` and `llms-full.txt` files already exist for GEO (generative engine optimization) — keep these updated as new features ship.
- Chinese-market versions (biomate-intro-v3-zh.mp4, quickstart ZH) already exist — prioritize WeChat Work integration in email drip for CN audience.
