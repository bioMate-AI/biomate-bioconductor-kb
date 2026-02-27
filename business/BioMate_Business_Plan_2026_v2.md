# BioMate AI — Business Plan
*Version 2.0 · February 2026 · Confidential*

**Company:** BioMate AI LLC
**Website:** biomate.ai
**Contact:** [founder@biomate.ai]

---

> **Confidentiality Agreement**
> Any information provided by BioMate AI LLC in this business plan, other than information that is in the public domain, is confidential in nature. Any disclosure or use of same may cause serious harm or damage to BioMate AI LLC. The reader agrees not to disclose it without express written permission.

---

# I. EXECUTIVE SUMMARY

BioMate AI is an **AI-powered research execution platform for life sciences**. A researcher describes their analysis in plain English — *"run differential expression on my RNA-seq data, FFPE tumor vs. normal, use DESeq2"* — and BioMate generates the computational pipeline, configures it for their data type, executes it on cloud or local infrastructure, and monitors quality control in real time.

## The Problem

Life science researchers spend **2–5 days per analysis** on pipeline debugging rather than doing science. The alternatives are expensive and slow:
- **Bioinformatics consultant:** $150–300/hour
- **Core facility:** $500–5,000/project, 2–8 week queue
- **In-house bioinformatician:** $120,000–180,000/year

This bottleneck does not exist because the analysis is scientifically hard. It exists because the tools require specialist configuration. A wet-lab researcher with a valid hypothesis abandons it — not because the biology is wrong, but because execution costs too much and takes too long.

## The Solution

BioMate collapses this bottleneck with three integrated capabilities:

- **Think:** Natural language understanding of research intent → workflow design → literature-grounded parameter recommendations
- **Execute:** 10,595 validated tools, 967 workflow templates, 20 scientific domains — run automatically from a single sentence
- **Govern:** Evidence-graded quality control thresholds (GOLD/SILVER/BRONZE, all with published citations) — the first platform where every QC decision is defensible and auditable

**Current status:** Production-ready. Running on AWS. Closed beta with invite-code system. Bioconductor (2,241 tools), Galaxy (8,354 tools), and nf-core (231 pipelines) fully integrated.

## Market Opportunity

| Metric | Value |
|---|---|
| Total Addressable Market | $250B+ global life science R&D spend |
| Serviceable Addressable Market | $23B bioinformatics software + analytical outsourcing |
| Serviceable Obtainable Market | 500,000+ computationally underserved researchers globally |
| Market CAGR | 20%+ (bioinformatics software) |

**Market timing signal:** In the 14 months from November 2024 to February 2026, four events defined this category: Sakana AI ($2.65B valuation), FutureHouse/Edison ($70M seed), Phylo/Biomni ($13.5M seed), NVIDIA + Eli Lilly ($1B joint AI lab). The category is being defined now.

## Competitive Position

BioMate is not an AI scientist (replacing researchers) and not an expert pipeline tool (serving bioinformaticians). It occupies a distinct position: **AI-powered execution infrastructure for the researcher who knows the biology but not the code.**

| | BioMate | Phylo/Biomni (closest AI-native competitor) | Seqera (closest execution competitor) |
|---|---|---|---|
| Validated tools | **10,595** | 82 | 500+ pipelines (expert-only) |
| Execution | **Full, natural language** | Limited | Full, code required |
| QC governance | **Evidence-graded, cited** | None | Manual |
| Researcher-friendly | **Yes** | Partial | No |
| Funding | Bootstrap / beta | $13.5M seed (Feb 2026) | Well-funded |

## Business Model

Freemium subscription → outcome-based pricing in Year 2.

| Tier | Price | Target |
|---|---|---|
| Free | $0/month | Academics, trial |
| Professional | $29/month | Individual researchers |
| Team | $79/user/month | Labs, core facilities |
| Enterprise | Custom | Pharma, CRO, clinical labs |

- **Break-even:** 78 Pro users ($2,247 MRR)
- **Gross margin:** ~89%
- **Year 1 target:** $289,320 revenue

## The Ask

BioMate is seeking seed funding ($500K–$800K), strategic partnerships (institutional pilots, NVIDIA Inception), and enterprise pilot programs. Funding will accelerate: public launch, first 10,000 users, enterprise sales hire, and academic publication strategy.

---

# II. COMPANY DESCRIPTION

## Mission Statement

To accelerate scientific discovery by making the full computational research cycle — from hypothesis to validated, reproducible result — fast, accessible, and affordable for every life science researcher.

## Company Philosophy and Vision

**Researcher-first design.** Every feature starts with one question: does this make the researcher's scientific work easier? BioMate removes computational friction; it does not replace scientific judgment.

**Honest AI.** BioMate automates pipeline execution, not scientific reasoning. We do not claim to replace researchers or generate autonomous discoveries. We claim to run analyses faster, more reliably, and more reproducibly than manual methods — and we can prove it.

**Open foundation.** BioMate is built on Galaxy (the world's most widely adopted open-source life science platform), Bioconductor (3,700+ R packages for genomic data analysis), and nf-core (community-curated Nextflow pipelines). Our tool catalog is community-validated. Our workflows are citable. Researchers can inspect, trust, and build on what we provide.

**Quality governance as a first-class feature.** The bioinformatics field lacks standardized, evidence-graded QC thresholds. BioMate's evidence-graded QC governance (every threshold cited to a published source, tiered GOLD/SILVER/BRONZE) is a scientific contribution, not just a product feature. This is the subject of a *Nature Methods* paper in preparation.

**Vision:** In five years, BioMate is the standard research execution infrastructure for academic and early-stage commercial life science. In ten years, BioMate is the operating layer through which a significant fraction of global life science computation flows — the way Stripe became the operating layer for global commerce.

## Goals and Milestones

| Milestone | Target Timeline |
|---|---|
| Closed beta → public beta launch | Month 1–2 |
| 1,000 active users | Month 3 |
| First institutional pilot partnerships (5) | Month 6–9 |
| 10,000 registered users | Month 9 |
| *Nature Methods* QC governance preprint | Month 9 |
| First enterprise contracts | Month 12–18 |
| $1M ARR | Month 18 |
| Outcome-based pricing tier launched | Year 2 |
| $10M ARR | Year 3–4 |

## Target Market

**Primary:** Wet-lab researchers (PhD students, postdocs, PIs) who generate experimental data — RNA-seq, WGS, proteomics, imaging — but lack bioinformatics expertise. Labs without dedicated bioinformatics staff. Bioinformatics core facilities overwhelmed by routine requests.

**Secondary:** Biotech startups, pharma discovery teams, CRO analytical divisions, clinical genomics labs requiring CLIA/CAP-compliant QC audit trails.

## Industry Description

BioMate operates at the intersection of three converging trends:

1. **AI-native research platforms (forming 2024–2026):** Investor conviction is established — $379M to Sakana, $70M to FutureHouse/Edison, $13.5M to Phylo/Biomni. The category leader is not yet determined.

2. **Bioinformatics software ($15B, 20%+ CAGR):** Currently dominated by expert-facing tools. The non-specialist majority — ~500,000 computationally underserved researchers — has no adequate solution.

3. **AI compliance gap:** Increasing pressure on reproducibility in published research and regulatory submissions creates demand for the specific capability BioMate provides: evidence-cited, auditable QC governance.

## Legal Structure

BioMate AI LLC. Founder-owned. Registered in the United States.

---

# III. PRODUCTS AND SERVICES

## Core Platform

BioMate is a web-based research execution platform. No installation. No infrastructure configuration. No code required.

### Capability 1 — THINK: AI Research Intelligence

A researcher types: *"I have RNA-seq data from FFPE tumor samples and matched normal tissue. I want to find differentially expressed genes related to immune evasion."*

BioMate responds with: recommended pipeline (DESeq2 with FFPE-specific QC profile), relevant tools, parameter recommendations based on FFPE tissue characteristics, and a literature-grounded rationale for each choice.

**Technical foundation:** Hybrid LLM inference — local model (handles 90% of queries, reducing cost by 84%) with cloud model fallback for complex reasoning. PhD-level biomedical NLP architecture applied to workflow generation.

### Capability 2 — EXECUTE: Automated Pipeline Execution

| Asset | Count |
|---|---|
| Validated scientific tools | **10,595** (Galaxy 8,354 + Bioconductor 2,241) |
| Workflow templates | 967 |
| nf-core Nextflow pipelines | 231 |
| Scientific domains | 20 |
| Execution backends | Local, AWS Batch, Slurm |

**Unique feature:** The researcher describes the goal. BioMate selects the tools, configures the parameters, and executes the pipeline — on local compute, AWS, or institutional HPC (Slurm). Real-time monitoring via server-sent events (SSE). Pilot mode: validate on a representative sample before committing to a full run.

**Scientific domains covered:** RNA-seq, single-cell RNA-seq, WGS/WES, ATAC-seq, ChIP-seq, metagenomics, cryo-EM (23-step SPA + 20-step cryo-ET), proteomics (LC-MS/MS, MaxQuant/DIA-NN), drug discovery (ADMET, docking, pharmacogenomics), and 11 more.

### Capability 3 — GOVERN: Evidence-Graded QC

This is BioMate's most defensible competitive differentiator. Every quality control threshold in BioMate has:

- A **published citation** (e.g., ENCODE4 guidelines, GATK best practices, Kraken2 benchmark papers)
- An **evidence tier**: GOLD (universally accepted consensus), SILVER (community standard), BRONZE (field heuristic)
- A **per-run audit log**: every threshold check, every override, logged with user identity and timestamp

**20 named QC profiles** covering: RNA-seq (5 profiles including FFPE, degraded RNA, low-input), DNA-seq (6 profiles including FFPE WGS, amplicon), single-cell (3 profiles), metagenomics (4 profiles), and cryo-EM (3 profiles including phase-plate).

**Clinical significance:** This system directly supports 21 CFR Part 11 compliance for clinical genomics labs — every QC decision is defensible in FDA audit. No competitor offers evidence-graded, citation-backed QC governance.

**Publication roadmap:** This framework is the subject of a *Nature Methods* paper in preparation (Month 9), with four subsequent domain-specific papers planned. Each paper simultaneously advances the science and drives platform adoption.

### Pricing Summary

| Tier | Price | Included | Target User |
|---|---|---|---|
| Free | $0/month | 100 AI queries, 10 workflows, 10 GB | Academics, evaluation |
| Professional | $29/month | 1,000 queries, 100 workflows, 100 GB | Individual researchers |
| Team | $79/user/month | 5,000 queries/user, 500 workflows, SSO | Labs, core facilities |
| Enterprise | Custom | Unlimited, on-prem option, HIPAA/SLA | Pharma, CRO, clinical |
| Outcome-based (Year 2) | $5–$150/analysis | Per delivered result | All segments |

**Value anchor:** Pro at $29/month = less than 12 minutes of bioinformatics consulting. This comparison is explicit in all marketing materials.

### Intellectual Property

- Proprietary AI architecture for biomedical intent classification and workflow generation
- Hybrid LLM inference system (84% cost reduction, patent-pending)
- Evidence-graded QC governance framework (publication in preparation)
- Pilot/QC gate system for large-scale run validation
- BioMate workflow orchestration engine

---

# IV. MARKETING PLAN

## Market Research

### Industry Size and Growth

| Market | Size (2024) | CAGR | Source |
|---|---|---|---|
| Global bioinformatics software | $15B | 20%+ | Grand View Research |
| Analytical CRO services | $8B+ | 12% | MarketsandMarkets |
| Life science R&D total spend | $250B+ | 7% | Statista |
| NIH annual budget | $47B | — | NIH |
| Number of active life science researchers | ~2 million globally | — | UNESCO |

**Addressable non-specialist researchers:** ~500,000 researchers generate sequencing or structural biology data but lack computational expertise to process it without assistance.

### Recent Market Formation Events (14 Months)

| Event | Date | Signal |
|---|---|---|
| Sakana AI Series B | Nov 2025 | $135M raise → $2.65B valuation; AI for research is fundable at scale |
| FutureHouse/Edison seed | Dec 2025 | $70M seed at $250M valuation; Eric Schmidt conviction |
| Phylo/Biomni seed | Feb 2026 | $13.5M from A16Z; direct competitor proves market exists |
| NVIDIA + Eli Lilly joint lab | Early 2026 | $1B investment; AI biology infrastructure is strategic |

**Conclusion:** The AI research platform category is being defined in 2025–2026. The category leader is not determined. BioMate must establish a position now.

---

## SWOT Analysis

### Strengths

| Category | Detail |
|---|---|
| Tool catalog | 10,595 validated tools — 100× more than nearest AI-native competitor (Phylo: 82) |
| QC governance | Evidence-graded, citation-backed thresholds — no competitor has this |
| Execution breadth | 20 scientific domains, 967 templates — Seqera serves 1 domain (Nextflow) |
| Open foundation | Built on Galaxy (50,000+ researcher network); trust inherited from day one |
| Team depth | Every member has 5+ years biomedical experience — unusual for AI startups |
| Cost structure | 84% LLM cost reduction via local inference; break-even at 78 Pro users |
| Clinical readiness | 21 CFR Part 11 audit trail, per-run QC logs — addressable CRO/clinical lab market |

### Weaknesses

| Category | Detail |
|---|---|
| Stage | Closed beta; no public users yet; no revenue validation |
| Brand | Not known in the researcher community yet |
| Team size | Small (5 people); execution risk across multiple priorities |
| Sales | No enterprise sales function; long institutional sales cycles (3–12 months) |
| Funding | Bootstrapped; limited runway for aggressive growth without investment |

### Opportunities

| Category | Detail |
|---|---|
| Market timing | Category forming now; 2025–2027 window to establish foundational position |
| Texas GTM | 63 identified priority targets (TMC, MD Anderson, UTSW, Baylor Genetics, Sonic Healthcare) |
| Clinical market | CLIA/CAP labs + CROs need exactly BioMate's QC audit trail; $500–5K/month ASP |
| Academic publishing | Papers citing BioMate in methods creates a cite-to-adopt pipeline |
| Outcome-based pricing | First bioinformatics platform with outcome-based pricing (94% margin potential) |
| Galaxy community | 50,000+ researchers are a pre-qualified, zero-cost distribution channel |
| DOE/USDA labs | Energy-biology convergence (MEOR, bioremediation, algae) — 9 national labs identified |

### Threats

| Category | Detail |
|---|---|
| Phylo/Biomni | Well-funded ($13.5M, A16Z), biology-specific, growing fast |
| Seqera expansion | Could add AI interface to existing execution platform |
| NVIDIA direct entry | NVIDIA could build a researcher-facing BioNeMo interface |
| LLM cost increases | Cloud API price increases reduce margins on fallback queries |
| Regulatory | HIPAA/GDPR compliance requirements grow as clinical data enters platform |
| Pace | Phylo raised $13.5M in Feb 2026 — window is closing |

---

## Competitive Analysis

### Competitor Data Collection

The following sources were used: company websites, pricing pages, PubMed/bioRxiv publications, Tracxn/Crunchbase funding data, Reddit r/bioinformatics community feedback, and direct platform evaluation.

### Competitive Landscape: AI-Native Research Platforms

| Platform | Org | Funding | Model | Tools | Execution | QC Governance | Price |
|---|---|---|---|---|---|---|---|
| **BioMate** | Startup (TX) | Bootstrap | Freemium + outcome | **10,595** | **Full (NL-driven)** | **Evidence-graded, cited** | $0/$29/$79/custom |
| Phylo/Biomni | Stanford spinout | $13.5M seed (A16Z, Feb 2026) | Freemium | 82 tools, 68 DBs | Limited | None | Free + paid (unannounced) |
| Edison/Kosmos | FutureHouse spinout | $70M seed ($250M val, Dec 2025) | Subscription | ~12 agents | Partial | None | Free / $200/mo |
| Sakana AI | Tokyo (ex-Google) | $379M total ($2.65B val) | Enterprise | N/A (paper generation) | None | None | ~$15/paper; enterprise |
| OmniScientist | Tsinghua (academic) | None (academic) | N/A | N/A | N/A | None | Free (research only) |

### Competitive Landscape: Execution Platforms (Expert-Facing)

| Platform | Model | Free Tier | Pro/Base | Compute | Researcher-friendly | AI layer |
|---|---|---|---|---|---|---|
| **BioMate** | Freemium subscription | 100 queries, 10 workflows | $29/month | Cost + 20% | **Yes** | **Full NL workflow gen** |
| Seqera | Open-core + SaaS | 250 runs, 3 users | Custom quote | $0.10/CPU-hr | No (expert only) | Limited |
| DNAnexus | Enterprise SaaS | None | Custom | 1.5–2.5× markup | No | None |
| Seven Bridges | Enterprise SaaS | None | Custom | Cost + premium | No | None |
| Terra/AnVIL | Platform + cloud | Limited | Pass-through | NIH-funded | No | None |
| Galaxy (OSS) | Open source | Unlimited (public) | Self-host | User pays cloud | Partial | **None** |

### Competitive Landscape: AI-Assisted Research Software

| Platform | Revenue | Model | What They Do | BioMate Overlap | BioMate Advantage |
|---|---|---|---|---|---|
| BenchSci | $104.9M (2023) | Enterprise SaaS | AI antibody/reagent search for pharma | Discovery phase only | BioMate executes the downstream analysis |
| Benchling | $100M+ ARR | Enterprise SaaS | ELN, LIMS, molecular biology tools | Lab data management | BioMate runs the computational analysis on the data |
| Geneious | N/A | Perpetual + subscription | Desktop sequence analysis | Sequence analysis overlap | BioMate covers 20 domains; cloud-native; AI-driven |

### Head-to-Head: BioMate vs. Phylo/Biomni (Closest Competitor)

Phylo/Biomni is the most direct competitor — both are AI-native, biology-specific, and target non-expert researchers.

| Dimension | BioMate | Phylo/Biomni |
|---|---|---|
| Validated tools | 10,595 | 82 tools, 68 databases |
| Scientific domains | 20 | ~10 |
| Full pipeline execution | Yes — Galaxy + Nextflow + AWS | Limited — primarily analysis recommendations |
| QC governance | Evidence-graded (GOLD/SILVER/BRONZE), cited | None |
| Audit trail | 100% per-run logging | None |
| Institutional integration | Galaxy ecosystem (50K+ researchers) | Standalone platform |
| Collaboration layer | Institutional-grade (shared histories, SSO) | Minimal |
| Clinical compliance (21 CFR) | Yes | No |
| Funding | Bootstrap (beta stage) | $13.5M seed (Feb 2026) |
| Time to market | Now (closed beta) | Launched Feb 2026 |

**BioMate's core advantage over Phylo:** Phylo recommends tools and generates analysis plans. BioMate *runs them* — end-to-end, with QC governance and audit trails. These are fundamentally different value propositions.

### Head-to-Head: BioMate vs. Edison/Kosmos (Autonomous Science)

| Dimension | BioMate | Edison/Kosmos |
|---|---|---|
| Primary focus | Execution platform for researchers | Autonomous AI scientist |
| User model | Researcher-guided | AI-autonomous (12-hour cycles) |
| Domain | Biology-specific execution | General science reasoning |
| Execution depth | 10,595 tools, 20 domains | ~12 autonomous agents |
| Audit trail | Full per-run | Partial |
| Price | $0/$29/$79/custom | Free/~$200/month |
| Positioning | Complement to researcher | Potential replacement |

**Conclusion:** Edison/Kosmos and BioMate serve different needs. Edison targets researchers who want AI to run a full research cycle autonomously. BioMate targets researchers who want to control the science but automate the computation. These are complementary, not head-to-head competitive.

---

## Marketing Expenses Strategy

| Channel | Action | Budget (Annual) | Expected Reach |
|---|---|---|---|
| GitHub (open-source presence) | QC threshold DB open-sourced; 20 repo topic tags | $0 | Organic researcher discovery |
| r/bioinformatics (120K members) | "Show Reddit" launch post | $0 | 500–2,000 views; 1–3% signup |
| nf-core Slack (10,000 users) | Announce as nf-core companion QC layer | $0 | Targeted, high-conversion |
| bioRxiv preprint | Post Paper 1 intro/methods draft | $0 | 1,000–5,000 views; citation pipeline |
| Twitter/X (@BiomateAI) | 3×/week: QC explainers, demo clips | $0 | Growing community |
| Conference presence | ISMB, ASHG, Galaxy Community Conference | $8,000 | Direct researcher contact |
| Cold email (Priority A targets) | After prior touchpoint only | $0 | 15–25% reply rate |
| Content / blog | Use-case walkthroughs per domain | $2,000 | SEO + researcher community |
| **Total Year 1 Marketing** | | **$10,000** | |

**Strategy principle:** Inbound-first. Cold email alone has <1% open rate. The sequence is: GitHub/Reddit/nf-core/preprint (inbound discovery) → conference touchpoint → email as closing step. Priority-A Texas targets (63 identified) include UTSW, MD Anderson, BCM HGSC, Baylor Genetics, Sonic Healthcare USA, TMC Innovation Hub, ARPA-H Dallas Hub.

---

## Pricing Strategy

### Value Anchoring

BioMate pricing is anchored against the cost of alternatives:

| Alternative | Cost | BioMate equivalent |
|---|---|---|
| Bioinformatics consultant | $150–300/hour | $29/month (Pro) |
| Core facility RNA-seq analysis | $500–2,000/project | $25/analysis (outcome-based) |
| In-house bioinformatician | $120–180K/year | $79/user/month (Team) |
| CRO analytical services | $5,000–50,000/project | Enterprise tier |

**Free tier design:** Generous enough to demonstrate full value (100 AI queries, 10 workflows). Not generous enough to replace a paid subscription for active research use.

### Outcome-Based Pricing (Year 2)

The field is moving from usage-based to outcome-based pricing. BioMate will be the first bioinformatics platform to adopt this model.

| Outcome | Price | Manual labor equivalent | Value ratio |
|---|---|---|---|
| Quick QC report | $5 | 30 min @ $60/hr = $30 | 6× |
| Standard RNA-seq pipeline | $25 | 4 hrs @ $60/hr = $240 | 10× |
| Single-cell RNA-seq | $75 | 1 day @ $60/hr = $480 | 6× |
| WGS alignment + variant calling | $150 | 3 days @ $60/hr = $1,440 | 10× |

**Margin comparison:**
- Usage-based compute markup: ~16% margin per workflow
- Outcome-based: **94% margin per successful workflow**

BioMate delivers 600–1,400× more value than it costs to run. Outcome-based pricing captures a small fraction of that value while still offering researchers an 85–95% discount vs. manual methods.

---

## Distribution Channel Assessment

| Channel | Type | Effort | Conversion | Revenue Potential |
|---|---|---|---|---|
| Galaxy ecosystem (50K users) | Organic / partnership | Low | Medium | High (free → pro conversion) |
| Academic publication (methods citations) | Organic | Medium | High | Medium (long-term compound) |
| nf-core community | Organic / technical | Low | High | Medium |
| Reddit r/bioinformatics | Organic | Low | Low-Medium | Medium |
| Direct cold email (Priority A) | Outbound | Medium | Medium (15–25%) | High per contact |
| TMC Innovation Hub (Houston) | Partnership | High | High | Very high (institutional deal) |
| ARPA-H Dallas Hub | Partnership / federal | High | High | Very high (federal program) |
| Conference (ISMB/ASHG) | Event | High | Medium | High (enterprise leads) |
| CRO/clinical lab referrals | Channel | High | High | High (enterprise tier) |

**Priority sequence:** Organic inbound (GitHub, Reddit, nf-core) in Months 1–3 → Texas Priority-A outreach in Months 1–4 → TMC/ARPA-H institutional partnership in Months 3–6 → Conference presence in Months 4–9 → Enterprise CRO/clinical sales in Months 9–18.

---

# V. OPERATIONAL PLAN

## Technology Architecture

### Frontend
- React web interface — no code, no installation required
- Natural language chat interface to AI assistant
- Real-time SSE monitoring dashboard (per-step progress, QC gate alerts)
- Compute settings UI: executor selection (local/Slurm/AWS Batch), per-invocation overrides

### Backend
- Python/Galaxy platform
- AI assistant: hybrid LLM (local model, 90% of queries; Anthropic/OpenAI fallback, 10%)
- Galaxy execution engine: 8,354 tools
- Nextflow execution engine: 967 templates, 231 nf-core pipelines
- Bioconductor knowledge base: 2,241 packages with workflows and data flows
- QC governance layer: 20 named profiles, per-run overrides, JSONL audit logs
- Billing infrastructure: Redis-backed, real-time quota management, 6 LLM providers

### Infrastructure
- AWS (us-east-1 + us-west-2), EC2 + Batch
- Storage: S3 (`biomate-nextflow-work`, `biomate-production-data`)
- Execution: Local, AWS Batch, Slurm (configurable per user)
- LLM: Local deployment (84% cost reduction) + cloud API fallback

## Current Platform Scale

| Asset | Count |
|---|---|
| Galaxy tools | 8,354 |
| Bioconductor packages | 2,241 |
| **Total validated tools** | **10,595** |
| Workflow templates | 967 |
| nf-core pipelines (Nextflow DSL2) | 231 |
| QC named profiles | 20 |
| Scientific domains | 20 |

## Development Roadmap

### Months 1–3 (Public Launch)
- Open public beta (free tier)
- Pro and Team billing live (Stripe)
- GitHub QC threshold database open-sourced
- nf-core Slack + Reddit launch posts

### Months 4–9 (Institutional Traction)
- SSO/SAML for institutional deployments
- Texas Priority-A outreach completed (63 targets)
- TMC Innovation Hub partnership proposal submitted
- *Nature Methods* QC governance preprint posted

### Months 10–18 (Enterprise)
- Enterprise compliance dashboard (audit export, SOC 2 prep)
- On-premise deployment option
- NVIDIA Inception partnership formalized
- CRO / clinical lab pilot programs (5 targets)
- Outcome-based pricing tier launched

### Year 2+
- Outcome-based pricing as default
- Asia-Pacific expansion
- Foundation model fine-tuning on domain-specific datasets

## Quality and Reliability

- **Pilot mode:** Validate large-scale runs on a representative sample before full execution — reduces wasted compute and catches errors early
- **QC governance:** Every threshold cited, every override logged, every run auditable
- **Reproducibility:** Any workflow can be re-run identically by any authorized user with one click
- **Security:** HIPAA-ready data handling; institutional SSO/SAML; role-based access

---

# VI. MANAGEMENT AND ORGANIZATION

## Leadership Team

### Founder / CEO

**Background:** PhD in Natural Language Processing and Machine Learning-Based Question Answering Systems. 12+ years in biomedical informatics.

**Why this matters:** BioMate's core technical challenge — understanding a researcher's scientific intent from natural language and generating a precise, evidence-grounded analytical plan — is a question-answering problem applied to biology. The founder built this capability as a research focus before building the company around it.

**Origin:** BioMate began when the founder's sister — a wet-lab researcher — waited more than two days every time she needed her own data analyzed. The founder had the skills to change that.

## Core Team

| Role | Background | Responsibility |
|---|---|---|
| **Founder / CEO** | PhD NLP/QA · 12+ yrs biomedical informatics | Vision · AI architecture · strategy |
| **Software Engineer** | 5+ yrs biomedical software | Full-stack · no-code UI · Galaxy frontend |
| **Backend Engineer** | 5+ yrs biomedical data infrastructure | API · pipeline orchestration · Galaxy core |
| **MLOps / DevOps** | 5+ yrs biomedical compute | LLM deployment · CI/CD · cloud execution |
| **Security Expert** | 5+ yrs biomedical data security | HIPAA/GDPR · audit trails · SSO |

**Team differentiator:** Every member has 5+ years of biomedical experience. This is rare among AI startups entering life science. BioMate's engineering decisions are grounded in real knowledge of how genomics pipelines fail, what QC thresholds mean, and what institutional procurement actually requires.

## Management Gaps and Hiring Plan

| Gap | Plan | Timeline |
|---|---|---|
| Enterprise sales | Hire after first 5 institutional pilot successes | Month 9–12 |
| Marketing / community | Contract hire for conferences and content | Month 3–6 |
| Scientific advisory board | 2–3 domain scientists from Galaxy community + academic collaborators | Month 6–9 |
| CFO function | Outsource until Series A | Ongoing |

## Organizational Chart

```
CEO / Founder
├── Software Engineer (full-stack, Galaxy frontend)
├── Backend Engineer (API, Nextflow/Galaxy orchestration)
├── MLOps / DevOps (LLM deployment, AWS)
└── Security Expert (HIPAA, SSO, audit)

Advisory Board (planned, Month 6–9)
├── Domain scientist advisors (2–3, Galaxy community)
├── Enterprise / pharma advisor
└── Research computing director (R1 university)
```

---

# VII. STARTUP EXPENSES AND CAPITALIZATION

## Current State

BioMate has been developed to production-ready beta stage with founder investment. The core platform — 10,595 tools, 967 workflows, AI assistant, QC governance, billing infrastructure — is built and running on AWS. Remaining investment requirements are in distribution, enterprise sales, and publication.

## Monthly Operating Expenses

| Category | Monthly | Annual |
|---|---|---|
| AWS infrastructure (EC2, S3, Batch) | $2,000 | $24,000 |
| LLM API costs (cloud fallback, ~10% of queries) | $500 | $6,000 |
| Domain, SSL, SaaS tools | $200 | $2,400 |
| Legal (IP, TOS, privacy) | — | $5,000 (one-time) |
| Conference presence | — | $8,000 |
| Marketing / content | $500 | $6,000 |
| **Total** | **$3,200** | **$51,400** |

## Break-Even Analysis

| Metric | Value |
|---|---|
| Fixed monthly costs | $2,000 (infrastructure) |
| Variable margin | ~89% |
| **Break-even MRR** | **$2,247** |
| Break-even in Pro users | 78 users × $29 = $2,262 |
| Break-even in Team users | 30 users × $79 = $2,370 |

## Funding Strategy

**Phase 1 — Bootstrap (now):** Achieve break-even through free-to-Pro conversion. Demonstrate product-market fit before raising external capital.

**Phase 2 — Seed round (Month 9–12):** Raise $500K–$800K anchored on:
- 10,000+ registered users
- 5 institutional pilot partnerships
- Demonstrated conversion rate and retention
- *Nature Methods* preprint posted

**Phase 3 — Series A (Year 2):** Raise $3M–$8M anchored on $1M ARR, enterprise references, and outcome-based pricing validation.

---

# VIII. FINANCIAL PLAN

## Year 1 Revenue Projection

| Revenue Stream | Detail | Monthly | Annual |
|---|---|---|---|
| Pro subscriptions | 150 users × $29/mo | $4,350 | $52,200 |
| Team subscriptions | 90 users × $79/mo | $7,110 | $85,320 |
| Enterprise accounts | 5 accounts avg $2K/mo | $10,000 | $120,000 |
| AI query overage | 50K queries/mo × $0.03 | $1,500 | $18,000 |
| Compute markup | 20% on $60K/yr spend | $1,000 | $12,000 |
| Storage | 5 TB × $0.03/GB/mo | $150 | $1,800 |
| **Total Year 1** | | **$24,110** | **$289,320** |

## Year 1 Cost Structure

| Category | Monthly | Annual |
|---|---|---|
| AWS infrastructure | $2,000 | $24,000 |
| LLM API (cloud 10%) | $500 | $6,000 |
| Payment processing (2.9%) | $700 | $8,400 |
| SaaS / operations | $300 | $3,600 |
| **Total variable costs** | **$3,500** | **$42,000** |

**Year 1 Gross Profit:** $289,320 − $42,000 = **$247,320 (~85% gross margin)**

*Note: Does not include team salaries (currently founder-funded or deferred). Enterprise is ~100% gross margin; subscriptions ~95%; compute markup ~20%.*

## 3-Year Revenue Projection (Conservative)

| Year | Registered Users | Paid Users | MRR | ARR | Gross Margin |
|---|---|---|---|---|---|
| Year 1 | 10,000 | 245 | $24,110 | $289,320 | ~85% |
| Year 2 | 50,000 | 1,200 | $85,000 | $1,020,000 | ~87% |
| Year 3 | 150,000 | 4,000 | $280,000 | $3,360,000 | ~89% |

*Year 2+ includes outcome-based pricing tier (target 20% of revenue at 94% margin), which drives overall margin expansion.*

## Key Unit Economics

| Metric | Value |
|---|---|
| Blended AI cost per query | $0.008 (local 90% + cloud 10%) |
| Overage revenue per query | $0.030 |
| Margin per AI query | 74% |
| LTV — Pro (24-month retention) | $696 |
| LTV — Team (24-month) | $1,896 |
| LTV — Enterprise (24-month) | $24,000+ |
| CAC target (Pro, organic) | $50 |
| LTV:CAC — Pro | 14:1 |
| Break-even MRR | $2,247 |

## Outcome-Based Pricing: Revenue Upside (Year 2)

Shifting from usage-based to outcome-based for heavy users dramatically improves per-workflow economics:

| Model | Price/RNA-seq run | Cost | Profit | Margin |
|---|---|---|---|---|
| Usage-based (current) | $1.52 | $1.27 | $0.25 | 16% |
| Outcome-based (Year 2) | $25.00 | $1.49* | $23.51 | **94%** |

*\*Includes 15% failure buffer at $1.27/run effective cost*

**Revenue comparison at 1,000 workflows/month:**
- Usage-based: $1,520 revenue, $250 profit
- Outcome-based: $25,000 revenue, $23,500 profit

## Use of Seed Capital ($500K–$800K)

| Use | Amount | Rationale |
|---|---|---|
| Enterprise sales hire | $120,000 | Required for Month 10–18 enterprise conversion |
| Marketing / community manager | $80,000 | Galaxy community, conferences, content strategy |
| Infrastructure scale (50K+ users) | $100,000 | AWS reserved capacity, database scaling |
| Academic publication budget | $50,000 | ISMB/ASHG/GCC conference presence, preprint fees |
| NVIDIA Inception integration | $30,000 | BioNeMo NIM integration engineering |
| Working capital | $120,000–$420,000 | 6–18 months runway |
| **Total** | **$500K–$800K** | |

---

# IX. APPENDICES

## Appendix A — Competitor Detail: Phylo / Biomni Lab

| Attribute | Detail |
|---|---|
| Funding | $13.5M seed (Feb 2026) — A16Z, Menlo/Anthology Fund (Anthropic partnership), Zetta, Conviction, SV Angel |
| Origin | Stanford SNAP Lab (Prof. Jure Leskovec); Biomni open-source project |
| Users | 7,000+ labs, biopharma, and healthcare organizations |
| Tools | 82 biology tools, 68 databases, 100+ software packages |
| Execution | Limited — primarily recommends tools and moves data between them; does not run full pipelines |
| Business model | Freemium — free tier with daily usage limits; paid features unannounced |
| **BioMate advantage** | 129× tool catalog; full pipeline execution; evidence-graded QC governance; Galaxy institutional layer; clinical compliance (21 CFR) |

## Appendix B — Competitor Detail: Edison / FutureHouse / Kosmos

| Attribute | Detail |
|---|---|
| Funding | $70M seed (Dec 2025) — Triatomic, Spark Capital; ~$250M valuation |
| Backing | Eric Schmidt; FutureHouse nonprofit → Edison Scientific commercial spinout |
| Capability | 12-hour autonomous research cycles; 1,500 papers/run; 79%+ reproducibility; 7 verified discoveries |
| Pricing | Free (10 credits/conversation); Kosmos ~$200/month; Enterprise custom |
| Positioning | AI replaces researcher for full research cycles |
| **BioMate distinction** | Edison is autonomous (AI drives); BioMate is researcher-guided (human drives, AI executes). These are complementary, not head-to-head. Edison users need BioMate to actually run the analyses Edison recommends. |

## Appendix C — Competitor Detail: Sakana AI

| Attribute | Detail |
|---|---|
| Funding | $379M total; $2.65B valuation (Nov 2025 Series B); MUFG, SMBC, Mizuho, NVIDIA |
| Origin | Founded 2023 by ex-Google researchers (Llion Jones co-authored "Attention Is All You Need") |
| Primary business | Japan-optimized enterprise AI — finance, manufacturing, government |
| AI-Scientist project | Open-source; ~$15/paper; 42% experiment failure rate; ML-focused, not biology-specific |
| **Relevance to BioMate** | Validates investor conviction in AI for research. Not a direct competitor — biology-specific execution is not Sakana's focus. |

## Appendix D — Competitive Timeline Comparison

| Platform | Founded | Open Source | Commercial Launch | Funding | Users |
|---|---|---|---|---|---|
| Sakana AI | Jul 2023 | Aug 2024 (AI-Scientist) | 2024 | $379M | Enterprise |
| FutureHouse | 2023 | May 2025 | Nov 2025 (Edison) | $70M | ~1,000 |
| Biomni/Phylo | 2024 | May 2025 | Feb 2026 | $13.5M | 7,000+ |
| **BioMate** | **2024** | **Planned** | **Beta now; public Month 1–2** | **Bootstrap** | **Beta** |

**Key lesson from competitor timelines:** Biomni took 18 months from research project to $13.5M funding. FutureHouse took 2 years. The common pattern: free public access → overwhelming demand → commercial raise. BioMate must reach this inflection point before well-funded competitors fully occupy the execution category.

## Appendix E — QC Governance: Evidence-Graded Thresholds

BioMate's QC governance layer is the company's most defensible technical differentiator. Summary:

| Domain | Named Profiles | Key Thresholds (Examples) | Evidence Tier |
|---|---|---|---|
| RNA-seq | 5 (standard, FFPE, degraded, low-input, single-end) | Alignment ≥85%; rRNA contamination <20% | SILVER (ENCODE) |
| DNA-seq (WGS/WES) | 6 (standard, FFPE, amplicon, clinical) | WGS coverage ≥30×; WES ≥80×; duplication ≤40% | GOLD (GATK BP) |
| scRNA-seq | 3 (standard, low-input, CITE-seq) | UMI ≥500; mito <20%; doublet rate <5% | BRONZE (field) |
| Metagenomics | 4 (standard, clinical, environmental, 16S) | Classification ≥30%; host removal ≥95% | SILVER (Kraken2) |
| Cryo-EM SPA | 3 (standard, low-contrast, phase-plate) | CTF fit quality ≥0.7; junk fraction <70% | SILVER (RELION) |

Full documentation: `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md`
Publication in preparation: *Nature Methods* (Month 9 target)

## Appendix F — Scientific Domains (20)

Biochemistry · Bioengineering · Bioimaging · Biophysics · Cancer Biology · Cell Biology · Database/Data Management · Genetics · Genomics · Glycoengineering · Immunology · Lab Automation · Literature/Knowledge Mining · Microbiology · Molecular Biology · Pathology · Pharmacology · Physiology · Synthetic Biology · Systems Biology

## Appendix G — Texas Go-to-Market: Priority-A Targets (12 of 63)

| Target | City | Segment | BioMate Fit |
|---|---|---|---|
| UT Southwestern Lyda Hill Bioinformatics | Dallas | Academic | Multi-omics, 8 faculty, national rank top-5 |
| BCM Human Genome Sequencing Center | Houston | Academic | 180+ staff, production-scale WGS/WES |
| MD Anderson Bioinformatics & Comp Bio | Houston | Academic | Top cancer center, TCGA-scale multi-omics |
| UTHealth McWilliams Biomedical Informatics | Houston | Academic | Only TX doctoral bioinformatics program |
| BCM Quantitative & Computational Biosciences | Houston | Academic | Multi-institution consortium (BCM+Rice+MD Anderson) |
| Rice University Treangen Lab | Houston | Academic | NSF/NIH metagenomics, energy-biology link |
| Baylor Genetics | Houston | Clinical lab | CLIA/CAP commercial genomics, BCM spinout |
| Texas Medical Center (umbrella) | Houston | Medical | World's largest medical complex, institutional deal |
| UT Southwestern Simmons Cancer Center | Dallas | Medical | NCI-designated, clinical trial data integrity |
| Sonic Healthcare USA | Austin | Diagnostic lab | US HQ in Austin, top-5 diagnostics company |
| NeuroX1 | Austin | Biotech | AI drug discovery startup, ADMET/proteomics fit |
| ARPA-H Dallas Hub | Dallas | Federal | $2.5B program, ecosystem partnership opportunity |

Full database (63 targets): `business/marketing/targets/texas_targets.json`

---

*BioMate AI LLC · biomate.ai · Confidential · February 2026*
