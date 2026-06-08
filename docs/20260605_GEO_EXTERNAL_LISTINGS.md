# GEO External Listings — Submission Content

**Date:** 2026-06-05  
**Purpose:** Ready-to-submit copy for Wikidata, Crunchbase, G2, and ProductHunt — the four highest-value third-party entity mentions for LLM GEO.

---

## 1. Wikidata

**Why it matters:** ChatGPT, Gemini, and Claude use Wikidata as a ground-truth entity database. A Wikidata item with a Q-identifier eliminates AI hallucination about BioMate's founding date, HQ, and capabilities. Once live, add the QID to `sameAs` in Organization JSON-LD on index.html and about.html.

**How to submit:**
1. Create a free account at https://www.wikidata.org
2. Go to https://www.wikidata.org/wiki/Special:NewItem
3. Enter item label and description, then add properties one by one
4. OR use QuickStatements (faster): https://quickstatements.toolforge.org/

### QuickStatements import (paste directly into QuickStatements)

```
CREATE
LAST|Len|"BioMate AI"
LAST|Den|"AI-powered computational biology and bioinformatics software platform"
LAST|Lde|"KI-gestützte Plattform für computergestützte Biologie und Bioinformatik"
LAST|P31|Q7397
LAST|P31|Q166142
LAST|P571|+2025-01-01T00:00:00Z/9
LAST|P856|"https://biomate.ai"
LAST|P17|Q30
LAST|P131|Q16555
LAST|P452|Q2996394
LAST|P366|Q2996394
LAST|P18|"biomate-ai-logo.png"
```

### Property-by-property reference

| Property | ID | Value |
|---|---|---|
| Instance of | P31 | Q7397 (software) + Q166142 (application software) |
| Inception | P571 | 2025 |
| Official website | P856 | https://biomate.ai |
| Country | P17 | Q30 (United States) |
| Located in | P131 | Q16555 (Houston) |
| Industry | P452 | Q2996394 (bioinformatics) |
| Described at URL | P973 | https://biomate.ai/about.html |
| Email address | P968 | mailto:contact@biomate.ai |

### Item text fields

**Label (English):** `BioMate AI`

**Description (English):** `AI-powered computational biology and bioinformatics software platform`

**Aliases (English):** `BioMate`, `biomate.ai`

**Statements to add manually (cannot be done via QuickStatements easily):**
- "has part" or "uses" → Nextflow (Q30070584), nf-core, AWS Batch
- "said to be the same as" → Crunchbase, ProductHunt (add after those profiles are live)

### Wikidata item — LIVE

**QID: Q140074014**  
**URL: https://www.wikidata.org/wiki/Q140074014**

`sameAs` updated in `index.html` and `about.html` Organization JSON-LD — DONE.

---

## 2. Crunchbase

**Why it matters:** Crunchbase profiles appear in Perplexity's "company overview" panels and are used by ChatGPT Plugins (and GPT-4o Browse) to verify startup existence and funding. DA ~80.

**URL after submission:** `https://www.crunchbase.com/organization/biomate-ai`

**How to submit (updated — the old /add/organization form no longer works):**

Crunchbase restricts free self-service submissions. The realistic paths are:

**Option A — Check if a stub already exists (fastest):**
1. Visit https://www.crunchbase.com/organization/biomate-ai in your browser
2. If a profile exists, click "Claim this profile" and verify with contact@biomate.ai
3. Fill in the fields below after claiming

**Option B — Via a Crunchbase Pro account:**
1. Subscribe to Crunchbase Pro at https://www.crunchbase.com/pricing
2. Use the dashboard to add a new organization
3. Fill in the fields below

**Option C — Via an investor/partner (free):**
1. Ask any investor, accelerator, or partner already on Crunchbase to add BioMate as a portfolio/partner company — they have edit access
2. Crunchbase also auto-discovers companies from press coverage — a TMC or GEN article will often trigger auto-creation

**Note:** The profile content below is ready to paste once you have access.

### Organization profile fields

| Field | Value |
|---|---|
| **Organization name** | BioMate AI |
| **Short description** (140 chars max — plain text, no special chars) | Agentic AI for biology. ADMET prediction, clinical trials, Bioconductor R library, 2455+ validated workflows. No coding required. |
| **Website** | https://biomate.ai |
| **Founded date** | 2025 |
| **HQ location** | Houston, Texas, United States |
| **Company type** | Private |
| **Operating status** | Active |
| **Employee count** | 1–10 |
| **Industry Groups** (Crunchbase fixed taxonomy — select from dropdown) | Science and Engineering |
| **Industries** (select from dropdown) | Biotechnology, Health Care, Software |
| **Sub-Industries** (if available) | Bioinformatics, Drug Discovery |
| **LinkedIn** | (add when available) |
| **Twitter/X** | (add when available) |

### Long description (for Crunchbase "About" section, ~300 words)

BioMate AI is an agentic computational biology platform that autonomously routes, executes, quality-grades, and remediates bioinformatics workflows through plain-English requests — no command-line expertise or dedicated bioinformatics staff required.

**Drug discovery and clinical pipeline.** BioMate covers the full pipeline from target identification to post-market surveillance: in silico ADMET prediction (30+ properties including hERG, CYP1A2/2C9/2C19/2D6/3A4, Caco-2, BBB penetration), virtual screening at scale (AutoDock Vina, GLIDE), PBPK pharmacokinetic simulation, BOIN Bayesian dose-escalation design for phase I trials, population PK modeling, IND filing support (§2.6.1–2.6.7 automated document assembly), and structured CRO submission packages.

**Full Bioconductor R ecosystem.** BioMate integrates the complete Bioconductor library — the largest curated repository of R packages for genomics, with 2,000+ peer-reviewed packages — making DESeq2, edgeR, limma, clusterProfiler, Seurat, monocle3, and hundreds of other R methods accessible through plain-English requests, executed on AWS Batch with full R environments.

**Omics, cell biology, and beyond.** Beyond drug discovery, BioMate covers the full breadth of modern biology: bulk and single-cell RNA-seq, spatial transcriptomics, whole-genome and whole-exome sequencing, ATAC-seq, ChIP-seq, proteomics (MaxQuant), metabolomics, metagenomics (QIIME 2), epigenomics, cell biology, immunology, cancer biology, glycobiology, rare disease, cryo-EM, cryo-ET, and structural biology — 37 biological domains in total.

**Agentic execution.** BioMate's AI agent autonomously: selects the best-fit pipeline from 2,455+ validated workflows, pre-fills parameters from research context, runs on AWS Batch, grades every output Gold/Silver/Bronze against published community standards (ENCODE, GTEx, nf-core, FDA, ICH), and automatically reruns with corrected parameters when a quality gate fails.

Key differentiators:
- Agentic auto-remediation loop — reruns on QC failure without user intervention
- ADMET prediction + full clinical trial pipeline (BOIN, popPK, IND filing) in one platform
- Complete Bioconductor R library (2,000+ packages) via plain-English requests
- 37 biological domains: omics, cell biology, drug discovery, structural biology, immunology, cancer, rare disease, and more
- HIPAA-compliant; BAA available; Private VPC deployment option
- Audit-ready outputs: parameter log, model version, corpus version on every result

Headquartered at the Texas Medical Center, Houston, Texas. Serves pharma R&D, biotech startups, academic labs, and core facilities.

Pricing: Free tier; Pro $49/month; Team $199/month; Enterprise — contact sales.

---

## 3. G2

**Why it matters:** G2 reviews appear directly in Perplexity answers for "best bioinformatics platform" queries. G2 category pages rank on Google. DA ~87.

**URL after submission:** `https://www.g2.com/products/biomate-ai/`

**How to submit:**
1. Go to https://www.g2.com/products/new
2. Claim or create the product profile
3. Use the fields below

### Product profile fields

| Field | Value |
|---|---|
| **Product name** | BioMate AI |
| **Tagline** | AI-powered bioinformatics for everyone |
| **Website** | https://biomate.ai |
| **Categories** | Bioinformatics Software, Drug Discovery Software, Life Science Software, AI/ML Platforms |
| **Pricing model** | Freemium + Subscription |
| **Starting price** | Free; paid from $49/month |
| **Deployment** | Cloud (SaaS) |
| **Target market** | Mid-Market, Enterprise, Small Business, Academic |
| **Industries** | Life Sciences, Pharmaceuticals, Biotechnology, Higher Education, Research |
| **Languages** | English |

### Product description (for G2, ~250 words)

BioMate AI is an agentic computational biology platform — an AI agent that autonomously selects, executes, quality-grades, and remediates bioinformatics workflows from plain-English requests. No coding, no pipeline setup, no bioinformatics staff required.

**Drug discovery and clinical pipeline:** In silico ADMET prediction (hERG, CYP inhibition, Caco-2, BBB, 30+ properties), virtual screening (AutoDock Vina, GLIDE), PBPK simulation, BOIN Bayesian dose-escalation design, population PK modeling, IND filing support (§2.6.1–2.6.7), and structured CRO submission packages — the full pipeline from target to trial in one platform.

**Full Bioconductor R ecosystem:** Integrates the complete Bioconductor library — the largest curated repository of R packages for genomics with 2,000+ peer-reviewed packages — including DESeq2, edgeR, limma, clusterProfiler, Seurat, and monocle3. All accessible through plain English, executed on AWS Batch.

**What makes BioMate different:**
- Agentic auto-remediation — AI reruns with corrected parameters on QC failure, no user intervention
- ADMET prediction + full clinical trial workflow in one platform
- Complete Bioconductor R library (2,000+ packages) via natural language
- 2,455+ validated workflows across 37 biological domains
- AI-graded QC: Gold/Silver/Bronze against ENCODE, GTEx, nf-core, FDA, ICH standards
- HIPAA-compliant — BAA available; Private VPC option

**Who uses it:** Drug discovery teams, medicinal chemists, computational biologists, core facility directors, and academic PIs.

### Key features to list on G2

1. Agentic workflow execution (autonomous routing, running, QC, remediation)
2. ADMET prediction — 30+ properties, hERG, CYP, Caco-2, BBB, AMES
3. Clinical trial pipeline — BOIN dose escalation, population PK, IND filing support
4. Full Bioconductor R library — 2,000+ peer-reviewed R packages via plain English
5. 2,455+ validated bioinformatics workflows across 37 domains
6. AI-graded QC (Gold/Silver/Bronze with community standards)
7. Auto-remediation loop on QC failure
8. Virtual screening at scale (AutoDock Vina, GLIDE, millions of compounds)
9. AlphaFold 2/3 + molecular docking integrated pipeline
10. Cryo-EM single-particle analysis (CryoSPARC, GPU-accelerated)
11. HIPAA compliance + BAA; Private VPC deployment
12. Audit trail (parameter log, model version, corpus version)
13. Structured DOCX report generation
14. Free tier available

---

## 4. ProductHunt

**Why it matters:** ProductHunt launches are cited by Perplexity and Bing Copilot in "new AI tools" queries. A successful PH launch also drives external backlinks from tech blogs.

**URL after submission:** `https://www.producthunt.com/products/biomate-ai`

**How to submit:**
1. Create account at https://www.producthunt.com
2. Go to https://www.producthunt.com/posts/new
3. Fill in fields below; schedule launch for Tuesday–Thursday 12:01 AM PT for best visibility

### Launch fields

| Field | Value |
|---|---|
| **Product name** | BioMate AI |
| **Tagline** (60 chars max) | Agentic AI for biology — ADMET, clinical trials, Bioconductor |
| **Website** | https://biomate.ai |
| **Topics** | Artificial Intelligence, Science, Health & Fitness, Developer Tools, SaaS |
| **Pricing** | Free |
| **Launch date** | (choose Tuesday–Thursday for maximum upvotes) |

### Description (250 words, for PH launch post body)

Hey Product Hunt! 👋

We built BioMate AI because the best computational biology tools — GATK, AlphaFold, DESeq2, CryoSPARC, AutoDock, the entire Bioconductor R library — have been locked behind command-line expertise and months of setup time.

**BioMate is an agentic AI that does the biology work for you.**

You describe what you need in plain English. BioMate's AI agent autonomously routes to the right pipeline, pre-fills parameters from your context, runs on AWS Batch, grades every output Gold/Silver/Bronze against published standards, and reruns with corrected parameters if something fails — no intervention needed.

**What's inside:**
- 🧬 Full drug discovery pipeline: ADMET prediction (hERG, CYP, BBB, 30+ properties) → virtual screening → PBPK simulation → BOIN clinical dose escalation → IND filing support
- 📦 Complete Bioconductor R ecosystem — 2,000+ peer-reviewed R packages (DESeq2, edgeR, Seurat, clusterProfiler…) via plain English
- 🔬 2,455+ validated workflows across 37 biological domains
- 🏗️ Structural biology: AlphaFold 2/3 + docking in one pipeline
- ❄️ Cryo-EM: CryoSPARC SPA from raw micrographs to publication map
- 🤖 Agentic QC: Gold/Silver/Bronze grading with auto-remediation on failure
- 🔒 HIPAA-compliant; Private VPC option; full audit trail on every result

**Free tier — no credit card needed.**

Small team at the Texas Medical Center, Houston TX. Building for pharma R&D, biotech, academic labs, and core facilities.

Questions about ADMET, Bioconductor access, or the clinical trial workflows? Ask below. 🙏

### Maker comment (short, for the comments section)

Curious what ADMET or Bioconductor workflows you're running today and what's slowing you down — we'd love to hear what BioMate should prioritize next.

---

## 5. After all submissions: update Organization JSON-LD

Once Wikidata, Crunchbase, and ProductHunt profiles are live, add `sameAs` to Organization JSON-LD in **both** `index.html` and `about.html`:

```json
"sameAs": [
  "https://www.wikidata.org/wiki/Q<REPLACE_WITH_QID>",
  "https://www.crunchbase.com/organization/biomate-ai",
  "https://www.producthunt.com/products/biomate-ai",
  "https://www.g2.com/products/biomate-ai/"
]
```

The `sameAs` field tells search engines and AI systems that all four entity records refer to the same real-world organization, dramatically strengthening entity coherence in knowledge graphs.

---

---

## 6. Wikidata — Connectors and Domains QuickStatements

Paste this into https://quickstatements.toolforge.org/ (logged into your Wikidata account). This adds connectors via P527 (has part) / P2283 (uses), and all 37 domains via P366 (has use).

```
Q140074014|P527|Q133436854
Q140074014|P527|Q63417942
Q140074014|P527|Q117130900
Q140074014|P2283|Q749568
Q140074014|P2283|Q7455583
Q140074014|P2283|Q2484994
Q140074014|P2283|Q743238
Q140074014|P2283|Q96237091
Q140074014|P571|+2025-01-01T00:00:00Z/9
Q140074014|P131|Q16555
Q140074014|P275|Q218616
Q140074014|P366|Q28946449
Q140074014|P366|Q193507
Q140074014|P366|Q1418791
Q140074014|P366|Q1068883
Q140074014|P366|Q15614164
Q140074014|P366|Q903778
Q140074014|P366|Q18409577
Q140074014|P366|Q12149006
Q140074014|P366|Q405
Q140074014|P366|Q128406
Q140074014|P366|Q902479
Q140074014|P366|Q904576
Q140074014|P366|Q101929
Q140074014|P366|Q815297
Q140074014|P366|Q862838
Q140074014|P366|Q7163
Q140074014|P366|Q7094
Q140074014|P366|Q7100
Q140074014|P366|Q2996394
Q140074014|P366|Q20737165
```

### Key mapping

| Statement | Property | Q-number | Label |
|---|---|---|---|
| Has part: MCP | P527 | Q133436854 | Model Context Protocol |
| Has part: Benchling | P527 | Q63417942 | Benchling |
| Has part: Opentrons | P527 | Q117130900 | Opentrons Labworks |
| Uses: REST | P2283 | Q749568 | REST |
| Uses: SSE | P2283 | Q7455583 | Server-Sent Events |
| Uses: Slack | P2283 | Q2484994 | Slack |
| Uses: OAuth | P2283 | Q743238 | OAuth |
| Uses: OpenAI API | P2283 | Q96237091 | OpenAI API |
| Inception | P571 | 2025 | — |
| Located in: Houston | P131 | Q16555 | Houston |
| License: proprietary | P275 | Q218616 | proprietary software |
| Has use: Transcriptomics | P366 | Q28946449 | transcriptomics |
| Has use: Genomics | P366 | Q193507 | genomics |
| Has use: Drug Discovery | P366 | Q1418791 | drug discovery |
| Has use: Epigenomics | P366 | Q20737165 | Epigenomics |
| Has use: Proteomics | P366 | Q15614164 | Proteomics |
| Has use: Metagenomics | P366 | Q903778 | metagenomics |
| Has use: Single-cell RNA-seq | P366 | Q18409577 | single-cell RNA-seq |
| Has use: Metabolomics | P366 | Q12149006 | metabolomics |
| Has use: Biology | P366 | Q420 | biology |
| Has use: Pharmacology | P366 | Q128406 | pharmacology |
| Has use: Cryo-EM | P366 | Q902479 | cryo-electron microscopy |
| Has use: Cryo-ET | P366 | Q904576 | cryo-electron tomography |
| Has use: Immunology | P366 | Q101929 | immunology |
| Has use: Systems Biology | P366 | Q815297 | systems biology |
| Has use: Synthetic Biology | P366 | Q862838 | synthetic biology |
| Has use: Genetics | P366 | Q7163 | genetics |
| Has use: Biochemistry | P366 | Q7094 | biochemistry |
| Has use: Biophysics | P366 | Q7100 | biophysics |
| Has use: Bioinformatics | P366 | Q2996394 | bioinformatics |
| Has use: Epigenomics | P366 | Q20737165 | Epigenomics |

**Note:** Slack (Q2484994), WeChat Work, SiLA2, and some instrument connectors may not have Wikidata items or the Q-numbers need verification. Add those manually after confirming the Q-numbers on wikidata.org.

---

## Priority order for submissions

| Platform | Effort | LLM Impact | Do first? |
|---|---|---|---|
| Wikidata | 20 min (QuickStatements) | Highest — used by ChatGPT, Claude, Gemini | Yes — do this today |
| Crunchbase | 15 min | High — Perplexity company panels | Yes — do this today |
| ProductHunt | 30 min | Medium — "new AI tools" queries | Second week |
| G2 | 20 min + reviews needed | Medium-High — "best bioinformatics" queries | Second week |

**Note:** G2 impact is highest once the product has 5+ verified reviews. After submission, ask early users and beta testers to leave G2 reviews.
