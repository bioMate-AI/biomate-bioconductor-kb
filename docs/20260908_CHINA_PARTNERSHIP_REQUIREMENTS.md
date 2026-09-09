# BioMate × China Hospital/Pharma Partnership — Requirements & Strategy Document

**Date:** 2026-09-08
**Status:** DRAFT for internal team review (English). To be converted to Chinese after review.
**Audience of this document:** our internal team + our China agent. (A separate, simpler English deck for the partner's *business* leadership follows this doc.)
**Origin:** partnership inquiry from a China-based agent. The partner side = a CEO + a business lead (non-technical), with deep, long-standing hospital relationships in China. Proposed model: co-develop a China-localized edition, they own the China market, revenue share; on-prem at hospitals with on-site maintenance by their engineers; joint hospital-based drug-R&D collaboration.

**Framing correction (read this first).** BioMate is first a **general bioinformatics/omics analysis platform** — a conversational front door over ~4,210 validated workflows, overwhelmingly omics/analysis (transcriptomics 1,695 · genomics 756 · epigenomics 265 · proteomics 184 · variant 181 · single-cell 105 · metagenomics 75 · metabolomics 57 · imaging 77 · etc.), with drug_discovery only ~200 workflows (~5% of the catalog). This document therefore leads with the **platform** and its **two audiences** (pharma R&D and hospital research), and treats **drug development as a separate, clearly-bounded track** — not the headline. Backing detail (fully cited) lives in two companion surveys: `docs/20260908_PLATFORM_FOR_PHARMA_NEEDS_VS_LANDSCAPE.md` and `docs/20260908_HOSPITAL_DEPARTMENT_RESEARCH_NEEDS_VS_BIOMATE.md`; the corrected three-part framing is in `docs/20260908_BIOMATE_THREE_PARTS_PHARMA_HOSPITAL_DRUGDEV.md`.

> **Honesty contract (read first).** This document states product maturity truthfully. Several China-critical capabilities are **not yet built** (Chinese UI, domestic-LLM support on-prem, on-prem/air-gapped/信创 deployment, departmental subsetting, IP-hardening). They are scoped here as the **joint build** the partnership funds — the China domestic on-prem edition — presented confidently as our approach, not as finished features, and not as a weakness. The partner-facing deck must not claim unbuilt capabilities as shipped.

---

## 1. The opportunity

China hospitals and pharma increasingly cannot use foreign cloud SaaS for genomic/clinical/omics work: patient genetic data is regulated (人类遗传资源 / Human Genetic Resources, PIPL, Data Security Law), and procurement increasingly mandates a **pure domestic product — 国产化 / 信创** (domestic software + hardware stack, self-controllable, on-prem). This requirement *excludes* most Western AI-bio platforms structurally. It is precisely the white space a **localized, on-prem, domestic-LLM edition of the BioMate analysis platform** can occupy, carried by a partner with real hospital relationships.

The core product being localized is a **general analysis platform for two audiences** — pharma R&D and hospital research — the same conversational-validated-workflow engine, differed only by use-case and framing. On top of that platform sit two revenue engines:
1. **Platform** — license/deploy the localized analysis platform to hospitals & pharma (recurring). This is the lead: the omics/analysis breadth is what most hospitals and pharma R&D groups actually need day-to-day.
2. **Co-development** — separately, use the platform + hospital data to jointly run drug-R&D programs (target → lead → IND-ready documentation), sharing upside in the assets/programs. Distinct track, honestly scoped (§4).

The partner's asset is **hospital access + market + regulatory navigation**; ours is the **platform + method**. The model aligns.

---

## 2. What BioMate is (plain language, for business people)

BioMate is a **general analysis platform for biomedical research** — a conversational AI front door over a large catalog of validated bioinformatics/omics pipelines. A scientist or clinician-researcher describes a goal in plain language ("find what distinguishes responders from non-responders in this cohort," "profile the microbes and resistance genes in these samples," "integrate the RNA, methylation and protein data for this disease question"), and BioMate selects and runs the right validated analysis pipeline on secure compute, then returns an auditable, report-grade result.

**Its real breadth is omics/analysis, not drug design.** From the live catalog (~4,210 validated workflows): transcriptomics/RNA-seq **1,695** · genomics **756** · epigenomics **265** · proteomics **184** · variant calling **181** · single-cell **105** · systems biology **108** · imaging **77** · metagenomics **75** · metabolomics **57** · pharmacology **39** · immunology **27** · structural biology + cryo-EM **~40** · drug_discovery **~200 (≈5%)** — plus multi-omics integration, patient stratification, and biomarker/target discovery. The platform's center of gravity is everyday omics analysis; drug development is a small, separate slice (§4).

Three things make it more than a tool collection:
- **One conversational front door** over the full validated-workflow catalog — the scientist doesn't need to know which tool or pipeline to pick, or how to run it on cloud/HPC/on-prem.
- **A closed, quality-gated loop** — every result passes automated QC gates with cited thresholds; failures trigger auto-remediation; nothing is presented as certain when it isn't (honest "held/unknown" states, no fabricated numbers).
- **Auditable, report-grade output** — versioned methods, provenance, and audit trail on every run — the reproducibility/provenance layer both hospital research and pharma R&D need.

The platform primitives are **audience-independent**: pharma R&D and hospital research use the *same* engine; only the use-case and framing differ.

---

## 3. Platform for Pharma R&D (the lead — one of two audiences)

The same analysis platform, framed for pharma R&D. The most acute, industry-wide analysis needs (multi-sourced in the pharma survey) are **self-service for bench scientists**, **reproducibility/provenance**, and **breaking the data-wrangling silos** — not molecule design. BioMate is strongest exactly there.

**Where it fits (honest):**
- **Self-service for bench scientists (ACUTE — the sweet spot).** The overwhelmed bioinformatician is the throughput cap; bench scientists "sit on data for months." Plain-language goal → auto-selected validated workflow directly relieves that bottleneck. 🟢
- **Reproducibility & provenance (ACUTE).** Validated catalog + QC gates + provenance/audit is report-grade reproducibility. 🟢 (Honest boundary: this is engineering-grade provenance — for China, the relevant bar is domestic 信创/等保 posture, addressed in §7, not Western GxP certification.)
- **Kill the data-wrangling tax / break silos (ACUTE).** The conversational front door removes the tool-knowledge barrier and lets scientists reach many pipelines through one interface. 🟡
- **Scale/cost orchestration, interpretation of hard cases, biomarker/stratification, safety-tox omics, proteomics/metabolomics** — all in-catalog; interpretation quality on hard cases and end-to-end evidence in some domains are the areas to validate.

**Differentiated shape:** BioMate is *both* the conversational co-scientist *and* the owner of a validated execution engine + QC gates + provenance — a combination the "AI co-scientist" players (which connect into third-party engines) and the workflow platforms (which need the scientist to know which pipeline to run) don't fully occupy. In China specifically, the compliant, on-prem, domestic-stack edition is a category most foreign platforms cannot enter at all.

---

## 4. Platform for Hospital research (department by department — the second audience)

The same analysis platform, framed for hospital translational/clinical **research** (clinician-scientists analyzing their *own* institutional cohorts). The one finding across every department: the **data-generation layer** (sequencers, scanners, panels) and the **clinical-report layer** (variant reports, biomarker scores, dosing) are well served by mature vendors — but the **research analysis layer in between** (re-analyzable pipelines, multi-omics integration, cohort analytics) is fragmented, gated behind a scarce bioinformatician, and not self-serve. That in-between layer is BioMate's target.

**Fit by department (from the hospital survey):**
| Department | Fit | Where BioMate fits / boundary |
|---|---|---|
| **Infectious Disease / Microbiology** | 🟢 **STRONGEST** | metagenomics (75) — taxonomy/AMR/outbreak phylogenetics, contamination-QC-gated, on-prem; matches send-out dependence + lab vacancies. Clinical CLIA sign-off stays with the lab. |
| **Immunology / Rheumatology** | 🟢 **STRONG** | single-cell (105) + immunology (27) + TCR/BCR repertoire + multi-omics → the siloed "no integrated immune-state readout" white space. |
| **Oncology / Molecular Tumor Board** | 🟡 strong analysis / GAP on reporting | tumor RNA-seq (fusions), variant calling, cohort biomarker discovery, stratification. **Not** the clinical actionability/MTB report. |
| **Medical Genetics / rare disease** | 🟡 strong pipelines / clinical-report GAP | secondary analysis + RNA-splicing + CNV/SV + reanalysis at scale. **Not** the graded clinical variant report. |
| **Hematology / Nephrology / Endocrinology / Neurology / Cardiology** | 🟡 PARTIAL | myeloid variant calling, clonal architecture, KPMP-style multi-omics, metabolomics, brain single-cell/spatial, PRS/GWAS — the "siloed, no multi-omic patient view" gaps. |
| **Radiology (research) / Pharmacy** | 🟡 PARTIAL | radiogenomics + reproducible radiomics; PGx star-allele + PK/PBPK modeling. Not clinical imaging-AI devices or bedside dosing CDS. |
| **Reproductive / Prenatal** | 🟠 weakest | research-only; NIPT/PGT are closed regulated IVDs. |

**The recurring value = the research analysis layer**, self-serve and reproducible, that no incumbent provides across omics domains together.

**The honest boundary (consistent everywhere):** BioMate runs the **analysis**; it does **not** produce the graded **clinical variant / ACMG report** — that stays a dedicated-vendor job, and the clinician signs the report. Device/IVD spaces (WSI-AI, imaging-AI, MRD, NIPT/PGT, bedside dosing) are out of scope. This boundary is a positioning strength, not a weakness: it keeps BioMate clearly on the research side of the clinical line.

---

## 4b. Drug development (a SEPARATE track — not the platform, not the lead)

**This is distinct from the analysis platform above** and is a small slice of the catalog (~200 drug_discovery + pharmacology workflows + specialized engines). It should be presented apart, and honestly scoped. The partner asked about lead compounds (先导化合物), candidate drugs (候选药), and efficacy validation (药物疗效验证):

**Real & tested — everything *around* generation (score / assess / document):**
- **先导化合物 (lead) — structure + docking + FEP** (AlphaFold/Boltz/Chai structure prediction; GNINA/Vina/DiffDock docking; OpenFE RBFE). 🟢
- **ADMET / safety assessment** — multi-endpoint (hERG/DILI/CYP-DDI/Ames), with an auto-loop QC gate. 🟢 in code — but **the auto-loop gate has not yet fired live on dev** (open issue). 🟡
- **候选药 (candidate) — PK/PBPK** (validated against a reference set) + **IND-ready documentation** (auto-assembled ICH M4 §2.6 nonclinical narratives with audit trail). 🟢 — with some regulatory fail-opens to close. 🟡
- **药物疗效验证 (efficacy, biology side)** — MoA from transcriptomics + biomarker/responder analysis on hospital cohorts — this is where the *hospital data + the analysis platform* create value and feed target/biomarker selection.

**Real but NOT wired / NOT built (the honest holes):**
- **Multi-objective optimization (MPO/DMTA) engine** — a real optimizer exists in code but **is not wired to the product** (no API/executor/UI). The single biggest latent capability, currently unusable end-to-end. 🟡
- **Trained, target-conditioned de-novo generator** — **not built** (today's generation is enumeration-based). 🔴

**Honest drug-dev framing for the partner:** for a *co-development* program we bring **target/biomarker (their data) → hit-to-lead & lead optimization scoring → safety/druggability assessment → IND-ready documentation** — everything around generation is built; the **trained generative core is the genuine hole** and the **MPO engine is unwired**. It is *not* "software that spits out a drug," and it is **not** the platform pitch — it is a separate co-development lane pursued selectively, on top of the platform.

---

## 5. Competitive landscape & our advantages

**Categories of competitors** (name only lightly in the deck; verify before asserting "no competitor"):
- **Foreign AI-bio / bioinformatics-cloud platforms** — strong tech, but **cannot meet China data-residency / 国产化 / 信创** and don't localize → largely excluded from hospital and increasingly pharma procurement.
- **Domestic Chinese bioinformatics / AI-drug vendors** — localized and compliant, but typically **point tools** (a sequencing-analysis pipeline, a docking service), not one conversational, quality-gated *analysis platform* spanning the omics/analysis breadth with self-serve access. Note: a compliant domestic full-stack drug-discovery competitor (e.g. XtalPi / 晶泰) exists — do not imply an open field on the drug-dev side.
- **CROs / in-house pipelines** — service or bespoke, not a self-serve platform.

**Our advantages (honest) — platform first:**
1. **Breadth as one governed analysis platform** — conversational front door over ~4,210 validated workflows across omics domains (transcriptomics/genomics/single-cell/metagenomics/proteomics/multi-omics…), not a single tool. This is the lead advantage for both audiences.
2. **Self-serve + closed QC loop + provenance** — plain-language access that relieves the bioinformatician bottleneck, with cited QC thresholds and auditable, reproducible output.
3. **Honesty engineering** — QC gates, cited thresholds, no fabricated numbers, "unknown when unknown" — trust with senior clinicians/researchers.
4. **A partnership that solves the localization/compliance blocker** — with the partner's hospital access, a **compliant on-prem domestic (国产化/信创) edition** is a category most foreign platforms structurally can't enter.
5. *(Separate drug-dev track only)* auditable IND §2.6 documentation and score/assess/optimize tooling — a co-development advantage, kept apart from the platform pitch and honestly scoped (§4b).

*(Do NOT over-claim "first / no competitor." Run a competitive pass before the deck asserts uniqueness.)*

---

## 6. Current product maturity (HONEST — for internal review)

| Area | Maturity |
|---|---|
| **Core analysis platform** (~4,210 validated omics/analysis workflows, conversational front door, AWS Batch execution, QC auto-loop, provenance/audit) | **Production-tested** (English, cloud) — this is the lead product |
| Depth of end-to-end run evidence across all omics domains | **Uneven** — some domains (proteomics/metabolomics/stratification) lack real end-to-end run evidence yet; validate during pilot |
| Drug-dev *(separate track, ~200 workflows)*: docking/FEP/ADMET/PBPK/IND | **Real & tested for score/assess/document**; MPO optimizer **unwired**, trained generator **not built** (the known holes) |
| Data-centric UI upgrade (dataset object, models module, cold-start, etc.) | **Built, in review — not yet merged/deployed** (this is recent work) |
| **Chinese UI / i18n** | **Not built** (English only) |
| **Domestic-LLM support (on-prem Chinese models)** | **Not built** (currently uses hosted foreign LLMs) |
| **On-prem / air-gapped / 信创 deployment** | **Not built** (currently cloud/AWS) |
| **Departmental subsetting / modular packaging** | **Not built** |
| **Hospital system integration (HIS/LIS/sequencer/ELN)** | **Not built** (generic upload today) |
| **IP-hardening for on-prem** | **Not built** |

The China edition is a **real engineering program**, not a repackage. This document scopes it.

---

## 7. China-specific requirements (the joint build)

These are the gaps that must be closed for the China market. Each is a work item.

### 7.1 Full Chinese localization (P0)
- UI, messages, reports, and **AI-generated narrative output** all in idiomatic Chinese (not literal calques).
- Chinese medical/genomic terminology, units, gene nomenclature; Chinese-population reference data where relevant (e.g. China-specific allele frequency resources).
- Bilingual toggle for research vs. export.

### 7.2 Domestic LLM support, on-prem (P0)
- Data cannot leave the hospital → **no hosted foreign LLM**. Must run **domestic, self-hostable models** (e.g. DeepSeek / Qwen / GLM-class) on the hospital's own GPUs, fully offline.
- Pluggable LLM layer: the platform's reasoning/routing/narrative must work against a **swappable, locally-served model** with graceful degradation when only a smaller model is available.
- (Aligns with our existing self-host inference direction — extend it to domestic LLMs + on-prem GPU.)

### 7.3 On-prem / air-gapped / 信创 deployment (P0)
- **Fully offline install** (no internet) — bundled containers, models, workflow images, reference DBs.
- Support **domestic stack**: domestic OS (麒麟/统信-class), domestic CPU/GPU (鲲鹏/昇腾-class), domestic DB (达梦-class) — at minimum a containerized deployment that runs on these.
- One-command, reproducible, updatable install; on-site update mechanism (the partner's engineers apply updates physically).

### 7.4 Data residency & compliance (P0)
- Compliance posture for **Human Genetic Resources Regulation, PIPL, Data Security Law, Cybersecurity Law**; hospital ethics/IRB workflows; audit logging for regulators.
- All patient/genetic data stays on hospital hardware; provenance + access control + e-signature (we already have audit-trail primitives — localize them).

### 7.5 Integration with hospital internal resources — input & output (P1)
- **Input**: ingest from hospital sequencers, LIS/HIS, PACS-adjacent omics stores, ELN — via configurable connectors, without manual re-upload; a connector SDK.
- **Output**: results back into hospital report systems / ELN / structured formats they consume.
- Honest data-residency labeling on every connector (on-prem / mounted / this-machine).

### 7.6 Modular / departmental subsetting (P1) — *the partner explicitly raised this*
- A department (e.g. infectious-disease microbiology, or immunology/rheumatology) needs only a **small subset** of the ~4,210 workflows/tools, not the whole catalog.
- **Capability packs**: ship per-department analysis bundles (e.g. "Microbiology metagenomics pack," "Immune multi-omics pack," "Oncology NGS pack") — smaller install, smaller model, focused UI, licensed independently. (A separate "Lead-Optimization pack" belongs to the drug-dev track, §4b.)
- The cold-start/module dashboard should present only the licensed subset; the source/tool registry must support subset builds.
- This also **reduces the attack surface for IP** (a department ships without the full method set) and lowers on-prem footprint.

### 7.7 Convenient tuning of functions, interactions & resources (P1) — *partner raised*
- On-prem admins must **configure without code**: enable/disable modules, set QC thresholds, map resources, choose the local LLM, adjust interaction flows/prompts.
- A config/admin layer (feature flags + resource registry + threshold editor + prompt/instruction packs) — some primitives exist (QC threshold editor, skills/instructions); make them a governed on-prem admin surface.

### 7.8 IP protection (P0) — *critical given on-prem + co-dev + a "cut-down" edition*
- On-prem means our code/models physically sit at the customer → must **not** ship inspectable core IP.
- Measures: ship **compiled/obfuscated** artifacts (not source); the **core generator/optimizer as a protected, license-gated module** (the crown-jewel method stays hardest to extract); **license keys + node-locking + expiry + tamper checks**; the **subset build** so no single site holds the whole method set; a clear **contractual IP split** in the JV (co-developed China-localization IP vs. our retained core platform/method IP).
- Decide what is *co-owned* (China localization, connectors, Chinese models tuning) vs *retained* (core platform, optimizer, generator).

---

## 8. Partnership & commercial model

**Proposed structure (partner's proposal, refined):**
- **Co-develop the China-localized edition** (the "阉割版"/subset edition scoped in §7). Joint build; funding/effort split TBD.
- **Partner owns the China market** — sales, hospital relationships, deployment, on-site maintenance (their engineers, trained + certified by us).
- **Revenue share** — by percentage, on both platform license revenue and co-development program upside. (Propose ranges internally before the meeting.)
- **Two revenue lines**: (a) platform licensing/subscription per hospital/department/pack; (b) **joint drug-R&D programs** (target→lead→IND) sharing asset/milestone upside with hospitals.
- **Maintenance & support**: partner's technical staff do on-site install/update/support; we provide L2/L3 remote (where allowed) + training + certification + a maintenance SLA.

**Roles:**
- *Us*: core platform + method, the localized build, domestic-LLM/on-prem engineering, IP-protected core, training.
- *Partner*: hospital access, market, regulatory/procurement navigation, on-site deployment & maintenance, pilot sourcing.

---

## 9. What we need the China partner to help with

- **A lighthouse pilot hospital** + a **specific department & disease/use-case** (concrete, data-available) to prove value — ideally one of the strongest-fit departments (infectious-disease/microbiology metagenomics, or immunology/rheumatology multi-omics) or another translational/omics group with a cohort-analysis or stratification need.
- **Access to the relevant gene/reference databases** and Chinese-population resources needed for localized analysis (and clarity on what's licensable/usable on-prem).
- **Regulatory & procurement navigation** — HGR/PIPL/信创 requirements, ethics/IRB, hospital IT/security review.
- **Real hospital data (under DUA)** for the pilot — governed, on-prem, never leaving the site.
- **A co-development disease/target** where hospital + platform jointly pursue 先导化合物.
- **Localization review** — medical Chinese terminology, report formats hospitals expect.
- **Deployment reality** — the actual on-prem hardware/OS/network constraints at target hospitals (to scope the 信创 build).

---

## 10. Sales / go-to-market strategy (China)

- **Land**: a paid pilot with a strongest-fit hospital department (one analysis capability pack, on-prem), tightly scoped to a value moment (a microbiology metagenomics run, an integrated immune multi-omics readout, or a cohort stratification result).
- **Expand**: additional analysis packs/departments in the same hospital; then adjacent hospitals via the partner's network.
- **Pharma**: the analysis platform for pharma R&D groups (self-serve omics/reproducibility) is the recurring lead; drug-dev co-development programs are a separate, selective lane on top.
- **Pricing**: per-department analysis capability-pack license (annual) + deployment/maintenance + optional (separate) co-development upside. Subset packs lower the entry price and the IP-exposure.
- **Moat**: compliance + localization + on-prem (国产化/信创) + the breadth of the validated analysis catalog + self-serve conversational access + QC/provenance — a bundle foreign platforms can't match and domestic point-tools don't have.

---

## 11. Phased roadmap (proposed)

- **Phase 0 — Alignment (weeks):** this doc → deck → partner meeting; pick pilot hospital/department/use-case; NDA + term sheet (IP split, revenue share); scope the 信创 target environment.
- **Phase 1 — Localized pilot MVP (≈1 quarter):** Chinese UI for the chosen capability pack; one domestic LLM on-prem; offline install on the pilot's stack; one hospital connector; the pilot use-case end-to-end; compliance/audit basics; IP-hardened build.
- **Phase 2 — Pilot & validation:** run the real use-case on real (governed) hospital data; iterate; produce the value evidence + a hospital reference.
- **Phase 3 — Productize the China edition:** more packs, more connectors, admin/tuning surface, formal 信创 certification path, maintenance SLA, JV operationalized.
- **Phase 4 — Co-development programs:** joint target→lead→IND programs with hospitals; asset-side economics.

---

## 12. Risks & mitigations

| Risk | Mitigation |
|---|---|
| IP leakage (on-prem + cut-down edition + co-dev) | Compiled/obfuscated artifacts; protected license-gated core; subset builds; contractual IP split; node-locking |
| Compliance (HGR/PIPL/信创) mis-step | Partner-led regulatory navigation; on-prem data-residency by design; audit/e-sign; ethics/IRB workflows |
| Domestic-LLM quality below hosted foreign models | Pluggable LLM layer + graceful degradation; rule-first extraction reduces LLM dependence; benchmark domestic models early |
| On-prem/air-gapped/信创 engineering underestimated | Containerized, reproducible install; scope the real target stack in Phase 0; start small (one pack) |
| Over-promising drug-R&D outcomes | Frame as co-development of the path (target→lead→IND); honest about the generator gap; no "drug from software" claims |
| Product maturity gaps (Chinese UI/on-prem not built) | This is the funded joint build; deck presents it as our approach, not shipped |
| Revenue-split / control disputes | Clear term sheet up front: markets, IP, maintenance, escalation |

---

## 13. Open questions for the partner meeting

1. Target hospital(s), department, and the first concrete use-case + available data?
2. The real on-prem environment (OS/CPU/GPU/DB/network — 信创 level, air-gapped?)?
3. Which domestic LLM(s) do their hospitals accept/prefer?
4. Which gene/reference databases are needed and licensable on-prem in China?
5. Revenue-share %, and IP-ownership split (localized IP vs. retained core)?
6. Co-development: which disease/target, and what asset-upside structure with the hospital?
7. Regulatory/procurement timeline realities (国产化 certification, ethics/IRB)?
8. Maintenance model: what can their engineers do on-site vs. what we support remotely?

---

## 14. Deliverables & next steps

1. **This requirements document** — internal team review.
2. **English deck** (simple, non-technical, for the partner's business leadership) — follows this doc; slide outline in the companion file `docs/20260908_CHINA_PARTNERSHIP_DECK_EN.md`.
3. After team review → **translate the deck (and, as needed, this doc) into idiomatic Chinese**; localize the UI-facing terminology.
4. Convert into the concrete Phase-0 term-sheet + pilot scope.

*Honesty note: maturity in §6 is stated truthfully; the deck must present unbuilt China capabilities (Chinese UI, domestic LLM, on-prem, subsetting, IP-hardening) as the co-developed program the partnership funds, never as shipped.*
