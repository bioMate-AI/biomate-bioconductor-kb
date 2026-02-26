# BioMate AI — Mentor Briefing
**Date:** February 26, 2026 · **Stage:** Closed Beta · **Confidential**

---

## What We Built

BioMate is an **AI-powered research execution platform for life sciences**. A researcher describes their analysis in plain English — "run differential expression on my RNA-seq data, FFPE tumor vs. normal, use DESeq2" — and BioMate generates the computational pipeline, configures it correctly for their data type, runs it on their infrastructure, and monitors quality control in real time.

**The core problem:** Wet-lab researchers have the biology questions. Bioinformatics infrastructure has the complexity. Most labs spend 2–5 days per analysis on pipeline debugging instead of doing science. Hiring a bioinformatician costs $120,000–180,000/year. Core facility analysis costs $500–5,000/project and takes weeks.

**What makes BioMate different:**

| | BioMate | Generic LLM (ChatGPT) | nf-core (pipelines) |
|---|---|---|---|
| Tool knowledge | 10,595 validated tools | Hallucinated | Curated but manual |
| QC governance | Evidence-graded, cited | None | Manual |
| Execution | Full (local/AWS/Slurm) | None | Manual config |
| Protocol awareness | 20 named QC profiles | None | None |
| Researcher skill required | None | Bioinformatics PhD | Nextflow expertise |

**Scientific domains covered:** RNA-seq, single-cell RNA-seq, WGS/WES, ATAC-seq, ChIP-seq, metagenomics, cryo-EM (full 23-step), proteomics (LC-MS/MS), drug discovery (ADMET, docking, pharmacogenomics), and 12+ more.

**Core innovation — Evidence-Graded QC Governance:** Every quality control threshold has a published citation and an evidence tier (GOLD = universally accepted; SILVER = community standard; BRONZE = field heuristic). This is the subject of a Nature Methods paper in preparation. No competitor has this.

---

## Current Status

**Platform:** Production-ready. Running on AWS. Closed beta with invite code system.

**Technical milestones completed:**
- 10,595 validated bioinformatics tools indexed (Galaxy + Bioconductor + nf-core)
- 967 workflow templates across 20+ scientific domains
- Full AWS Batch + Slurm + local execution
- Billing infrastructure (Redis-backed, per-user quota management, 6 LLM providers)
- QC governance layer: 20 named profiles, per-invocation overrides, audit logs
- Cryo-EM pipeline: full 23-step SPA + 20-step cryo-ET (CryoSPARC + RELION)

**Publication roadmap (in preparation):**
1. **Nature Methods (Month 9):** QC governance framework — evidence-graded thresholds for 6 sequencing domains
2. **Genome Biology (Month 15):** Metadata-inferred QC profile suggestion (ML problem)
3. **Nature Methods / Nat Comms (Month 20):** Cryo-EM SPA benchmark — 23-step pipeline, EMPIAR datasets
4. **Nature (Month 24):** HCA reanalysis — QC biases in 600+ scRNA-seq datasets, 50M cells
5. **Nature Chemical Biology (Month 30):** Drug discovery QC governance — proteomics, ADMET, pharmacogenomics

Each paper simultaneously advances the science and drives platform adoption among researchers who cite the methodology.

---

## Go-to-Market Strategy

### Why Texas First

Texas has the highest density of immediately reachable targets of any U.S. state:
- **Texas Medical Center (Houston):** Largest medical complex in the world — 60+ institutions, 106,000 employees
- **UT Southwestern (Dallas):** Top-5 bioinformatics department nationally (Lyda Hill Department)
- **MD Anderson:** World's top-ranked cancer center — heavy multi-omics pipeline usage
- **Baylor College of Medicine HGSC:** 180-person genomics center, Human Genome Project founding member
- **Texas A&M + Rice + UT Austin:** Major metagenomics, synthetic biology, agricultural genomics programs

### The Energy-Biology Angle (Texas Unique)

Texas sits at the intersection of the world's largest energy industry and a growing genomics infrastructure. **No other bioinformatics platform is serving this market.**

Three concrete applications:
1. **MEOR (Microbially Enhanced Oil Recovery):** Metagenomics identifies oil-displacing microbes in petroleum reservoirs. Targets: ExxonMobil research, Texas A&M Petroleum Engineering, UTMB Galveston.
2. **Bioremediation genomics:** Companies like Igenbio (Houston) explicitly offer genome sequencing for bioremediation acceleration — BioMate's metagenomics workflows are a direct product fit.
3. **Algae biofuels:** UT Austin (UTEX — world's largest algae collection) + Texas A&M (world record: 43.3 g/m²/day biomass productivity) are global leaders. ExxonMobil invested $600M in algae biofuels synthetic biology.

This positions BioMate for **energy company R&D partnerships** — a market with larger budgets and longer contract durations than academic labs.

### Target Database (Built)

We have a curated database of **79 targets** across 5 segments, all with priority scores, domain tags, BioMate workflow mapping, and contact information:

| Segment | Targets | Priority A | Energy-linked |
|---|---|---|---|
| Texas (academic + medical + biotech) | 45 | 12 | 12 |
| DOE National Laboratories | 9 | 3 | 7 |
| Gulf Coast energy corridor | 8 | 0 | 4 |
| Agricultural genomics belt | 8 | 2 | 0 |
| Clinical labs / CROs | 9 | 4 | 0 |
| **Total** | **79** | **21** | **23** |

A CLI marketing agent (`outreach_agent.py`) generates personalized email drafts for each target on demand.

### Outreach Channel Strategy

Cold email alone has <1% open rate. The strategy prioritizes **inbound discovery first, email as the closing step:**

| Channel | Action | Expected Reach |
|---|---|---|
| **GitHub** | 20 repo topic tags + open-source QC threshold DB | Organic discovery by researchers |
| **r/bioinformatics** (120K members) | "Show Reddit" launch post | 500–2,000 views, 1–3% signups |
| **nf-core Slack** (10,000 users) | Announce as nf-core companion layer | Targeted, high-conversion audience |
| **bioRxiv preprint** | Post Paper 1 intro/methods draft | 1,000–5,000 views; inbound citations |
| **Twitter/X @BiomateAI** | 3x/week: QC explainers, energy angle | Growing community presence |
| **Cold email (Priority A)** | After prior touchpoint | 15–25% reply rate (vs. <1% cold) |

**Texas-specific outreach sequence:**
1. **Weeks 1–4:** Houston Medical Center cluster — TMC Innovation Hub, MD Anderson, BCM HGSC, UTHealth
2. **Weeks 3–6:** Dallas academic — UT Southwestern Bioinformatics Dept, ARPA-H Dallas Hub
3. **Weeks 5–8:** Austin biotech — NeuroX1, Colossal, XBiotech, UT Austin
4. **Weeks 6–10:** Energy-biology vertical — Igenbio, ExxonMobil, Texas A&M MEOR, UTEX algae

---

## Business Model

**Pricing tiers:**
- **Free:** $5/month compute credit included, limited to 3 workflows/month — acquisition and trial tier
- **Professional:** $29/month — unlimited workflows, 90-day beta discount to $0
- **Team:** $79/user/month — shared workflows, institutional access controls
- **Enterprise:** Custom — HIPAA-ready, dedicated compute, SLA, procurement-compatible

**Revenue targets:**
- Break-even: 78 Pro users or 30 Team users ($2,247 MRR)
- Year 1: 10,000 registered, 150 Pro, 90 Team → **$289,320 revenue**
- Year 3: $326M+ ARR (projection from business plan)

**Gross margin: ~89%** — primary cost is LLM inference (mitigated by hybrid local model for 90% of queries) and AWS compute (passed through at cost).

**FDA/compliance opportunity:** Evidence-graded QC + full audit logs position BioMate for the **21 CFR Part 11** clinical genomics market (CROs, clinical labs, pharma) — higher ASP ($500–5,000+/month enterprise contracts) and longer retention than academic.

---

## What I'm Seeking Mentor Input On

1. **Texas vs. National first:** Should we concentrate entirely on Texas for the first 6 months (depth over breadth) or run Texas + DOE labs + CRO outreach in parallel?

2. **Energy-biology positioning:** Is the MEOR/bioremediation/algae angle a distraction from the core academic market, or a genuine differentiated wedge worth doubling down on? It's a larger budget market but requires different messaging.

3. **Publication strategy as GTM:** We're using academic papers (Nature Methods, Genome Biology) as marketing vehicles — co-authors become users, citation networks drive discovery. Is this the right pace for a software company, or should we be moving faster to pure commercial GTM?

4. **Pricing for the Texas market:** Academic labs are price-sensitive; medical centers and biotech have procurement processes. Should we lead with the free tier for academics and a different pitch for institutional buyers, or unify the message?

5. **Partnership vs. direct sales:** TMC Innovation Hub and ARPA-H Dallas Hub are natural partnership anchors. Is an institutional partnership (embed BioMate as default infrastructure for hub members) worth pursuing early, even at a discounted/free rate?

---

## Key Materials Available

| Document | Location |
|---|---|
| Full business plan (50 pages) | `business/BioMate_Business_Plan_2026.md` |
| Investor deck (HTML) | `business/investor_deck.html` |
| Texas GTM strategy (detailed) | `business/marketing/TEXAS_STRATEGY_20260226.md` |
| 79-target database | `business/marketing/targets/*.json` |
| Priority-A email drafts | `business/marketing/public_channels/priority_A_texas_emails.txt` |
| AWS release plan | `business/20260224_1154_RELEASE_PLAN_AWS_PUBLIC_BETA.md` |
| QC evidence document | `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md` |
