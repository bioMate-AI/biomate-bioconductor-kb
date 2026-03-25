# BioMate AI — Pilot Study Preparation Brief
*Prepared for Partner Meeting · March 2026 · Confidential*

---

## Purpose

This document addresses the three preparation areas requested for our Week 5 meeting:

1. **Pilot Study Partner Outreach** — who to approach and why
2. **Core Assumptions & Hypothesis Definition** — what the pilot is designed to validate
3. **Technology Stack Readiness** — honest assessment of all three platform layers

---

## Part 1: Pilot Study Partner Outreach

### Overview

Drug development is the primary focus of the pilot program. All five research directions serve this overarching goal — from molecular discovery through multi-omics characterisation, structural biology, and genomic profiling. One partner is identified per direction.

| # | Direction | Market (2025→Proj.) | CAGR | BioMate State | Partner |
|---|---|---|---|---|---|
| A | Drug Discovery | $2.4–3.6B → $16.5–49.5B (2034) | 25–30% | COMPLETE — 12 phases, 9 QC profiles | UT Southwestern Simmons Cancer Center |
| B | RNA-seq / Precision Medicine | $4.45B → $11.1B (2030) | 20.1% | SUBSTANTIAL — 186 tools, 5 QC profiles | Texas Children's Hospital |
| C | Cryo-EM + AI Structures | $1.42B → $6.6B (2033) | 19.3% | COMPLETE — SPA+ET, 23+5 steps, 43 tests | UT Southwestern Cryo-EM Facility |
| D | Single-Cell Perturbation | $4.3B → $13.7B (2030) | 18.7% | PARTIAL — 79 tools, 3 QC profiles | Baylor College of Medicine — Center for Cell and Gene Therapy |
| E | Multi-Omics (Prot.+Metab.) | $3.1B → $12.6–13.2B (2035) | ~15% | PARTIAL — LC-MS cataloged; wrappers TBD | St. Jude Children's Research Hospital |

---

### Direction A — Drug Discovery
**Partner: UT Southwestern Simmons Cancer Center**

| | |
|---|---|
| **Use case** | Cancer target identification, lead optimisation, ADMET filtering on oncology compound libraries |
| **Why this partner** | Active oncology drug programs with real compound data. FDA-submission QC audit trail is a direct differentiator. BioMate's 12-phase pipeline covers every step they need. |
| **Pilot scope** | 4 weeks · ADMET screening + molecular docking on 10–20 real compounds |
| **Deliverable** | QC audit log + exportable methods report |
| **Evidence goal** | Time-to-result vs. prior manual approach; ADMET pass rate |
| **Readiness** | 🟢 Ready now |

---

### Direction B — RNA-seq / Precision Medicine
**Partner: Texas Children's Hospital — Research Institute**

| | |
|---|---|
| **Use case** | Pediatric mRNA / RNA-seq: tumor vs. normal differential expression, pathway enrichment for disease mechanism studies |
| **Why this partner** | TCH runs RNA-seq studies on pediatric cancer cohorts. Manual pipeline setup is a bottleneck. BioMate's DESeq2/edgeR workflows with ENCODE-cited QC thresholds produce publication-ready output. |
| **Pilot scope** | 4 weeks · FastQC → STAR alignment → DESeq2 → pathway enrichment (clusterProfiler) → exportable QC report |
| **Deliverable** | HTML/PDF methods report; QC audit log |
| **Evidence goal** | Time-to-result; QC audit log rated as publication-ready by PI |
| **Readiness** | 🟢 Ready now — can start with a public GEO dataset |

---

### Direction C — Cryo-EM + AI Structures
**Partner: UT Southwestern Cryo-EM Facility**

| | |
|---|---|
| **Use case** | CryoSPARC standard SPA on membrane proteins or viral particles; benchmarking BioMate processing vs. manual curation |
| **Why this partner** | UT Southwestern has an established cryo-EM facility with active structural biology projects. BioMate's 23+5 step pipeline and 43 automated tests cover SPA end-to-end with EMDB-aligned QC thresholds. |
| **Pilot scope** | 4–6 weeks · CryoSPARC SPA on partner's raw micrographs or an EMDB-deposited dataset |
| **Deliverable** | Refined map + QC report (resolution estimate, CTF fit, particle count) |
| **Evidence goal** | Time-to-map vs. manual processing; QC thresholds validated against EMDB deposition standards |
| **Readiness** | 🟢 Ready now |

---

### Direction D — Single-Cell Perturbation
**Partner: Baylor College of Medicine — Center for Cell and Gene Therapy**

| | |
|---|---|
| **Use case** | Cell therapy development; single-cell immune profiling of engineered cell products |
| **Why this partner** | Active cell therapy programs requiring single-cell characterisation. scRNA-seq clustering and trajectory analysis are directly applicable without needing CRISPR screen capability. |
| **Pilot scope** | 4 weeks (staged) · Month 1: Seurat/Scanpy clustering → UMAP → cell-type annotation → differential abundance. Month 2+: perturbation analysis once CRISPR screen sprint is complete. |
| **Deliverable** | Annotated cell atlas + differential abundance report |
| **Evidence goal** | Time-to-cell-type-annotation vs. manual Seurat workflow; QC pass rate |
| **Readiness** | 🟡 scRNA-seq ready now. CRISPR screen subworkflow requires a 2-week engineering sprint before Month 2. |

---

### Direction E — Multi-Omics (Proteomics + Metabolomics)
**Partner: St. Jude Children's Research Hospital — Department of Chemical Biology & Therapeutics**

| | |
|---|---|
| **Use case** | DIA-LC-MS/MS proteomics: protein quantification from cancer cell lines or patient plasma; ADMET metabolite profiling |
| **Why this partner** | St. Jude runs large-scale proteomics studies. The `LC-MS-agent` already exists in BioMate; integration sprint is 1 week. MaxQuant/DIA-NN output → BioMate QC → statistical analysis → exportable report. |
| **Pilot scope** | 4–6 weeks · MaxQuant output → proteomics QC (CV, missing values, dynamic range) → DEP/limma differential abundance → pathway enrichment |
| **Deliverable** | Exportable QC report + methods section text |
| **Evidence goal** | Time-to-report vs. manual R script pipeline; QC metrics match internal lab standards |
| **Readiness** | 🟡 Requires 1-week LC-MS-agent integration sprint before pilot begins. Schedule for Week 5–6 of overall program. |

---

### Outreach Message Template

> "BioMate is a production-ready AI research execution platform — plain English query to fully executed, QC-governed bioinformatics pipeline. We are running a 4-week pilot program with **five** research groups, one per domain. We cover all compute costs; you provide one researcher and one real analysis use case. At the end you receive an exportable methods report and QC audit log suitable for inclusion in a manuscript. In return, we ask for written feedback on time savings and output quality. Would your group be interested in the [RNA-seq / proteomics / cryo-EM / drug discovery / single-cell] track?"

---

## Part 2: Core Assumptions & Hypothesis Definition

### What the Pilot Is Designed to Test

The Evidence-Based Business Model requires validating assumptions before scaling. Below are the critical ones the pilot study will test, written as falsifiable hypotheses.

---

### Assumption 1: Workflow Generation Quality
**Assumption:** BioMate can generate a correct, executable bioinformatics workflow from a plain-English query without researcher intervention.

**Hypothesis:** ≥80% of workflows generated during the pilot run end-to-end without a manual parameter correction by the researcher.

**How to measure:** Log correction events via UX telemetry; count interventions per session. Success = ≤1 manual correction per 5 workflows.

**Current evidence:** Drug discovery 12-phase pipeline confirmed working end-to-end on AWS; RNA-seq confirmed on public datasets. Known gap: some ADMET tools (e.g. DeepPurpose) require local installation on partner infrastructure.

---

### Assumption 2: QC Governance Is Defensible
**Assumption:** BioMate's GOLD/SILVER/BRONZE QC thresholds are recognized as valid by domain researchers and are sufficient for inclusion in a publication methods section.

**Hypothesis:** ≥70% of pilot researchers rate the QC output as "publication-ready or near publication-ready" in the exit survey.

**How to measure:** Exit survey (5-point Likert scale) + qualitative review of QC audit log by domain expert.

**Current evidence:** QC thresholds are cited to peer-reviewed sources (ENCODE, GATK best practices, EMDB guidelines). QC gate evidence framework documented in `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md`. Exit survey component not yet implemented (see Technology Readiness gap below).

---

### Assumption 3: Time Savings Are Meaningful
**Assumption:** BioMate reduces analysis turnaround time from days to under 30 minutes for a standard workflow.

**Hypothesis:** Median time from query submission to completed workflow result is <30 minutes for RNA-seq end-to-end (standard 50M-read, 3 replicates vs. 3 controls).

**How to measure:** Timestamp query submission → workflow completion event in backend telemetry. Compare to self-reported prior experience in intake survey.

**Current evidence:** Workflow generation (AI → Nextflow file) takes 3–10 seconds. Nextflow execution on AWS is compute-dependent: FastQC (~5 min), STAR alignment (~15 min per sample), DESeq2 (~5 min). Total realistic range: 25–90 min depending on sample count and compute tier.

---

### Assumption 4: Pricing Is Accessible
**Assumption:** $29/month is within the discretionary budget of an individual academic researcher.

**Hypothesis:** ≥60% of pilot participants indicate they would pay $29/month from their own lab budget after the free trial period.

**How to measure:** Explicit question in exit survey: "Would you purchase BioMate at $29/month?" + "From which budget line?"

**Current evidence:** Strategic Window Analysis rates customer price sensitivity as a moderate-to-high threat for individual researchers (postdocs often pay from personal budgets). Institutional (core facility) pricing model may be a lower-friction path for early revenue.

---

### Assumption 5: The AI Engine Does Not Hallucinate Critical Steps
**Assumption:** BioMate's tool catalog (10,595 validated tools) prevents the AI from recommending steps that do not exist or parameters that are incorrect for the data type.

**Hypothesis:** Zero pilot workflows include a tool call that fails due to a non-existent tool name or a parameter that is incompatible with the specified data type.

**How to measure:** Monitor Nextflow execution logs for `Command not found` and parameter validation errors. Distinguish from infrastructure errors (missing module on partner system).

**Current evidence:** L0 cache (pre-validated workflow patterns), L2 validation (tool-plan validation before generation), and the unified tool index enforce this constraint. Known gap: tool availability on partner infrastructure is outside BioMate's control.

---

### Primary Pilot Objective (One-Sentence)

> **Validate that a non-bioinformatician researcher can run a publication-ready analysis workflow on their own data in under 60 minutes, producing a QC-audited result they trust, at a cost sustainable under a grant budget.**

---

## Part 3: Technology Stack Readiness Assessment

The pilot study document identifies three layers. Below is an honest assessment of each.

---

### Layer 1: Website / Front-End Interface

**What is working:**
- Chat interface with natural language query input ✅
- Workflow artifact viewer with execution controls (Pause, Resume, Cancel, QC Gate) ✅
- Run Manager panel — shows all active and historical workflow runs ✅
- Active-runs status bar on main chat page (always visible, no button required) ✅
- In-app toast notifications when a workflow completes or fails ✅
- Stop button for AI reply (AbortController) + soft message queue ✅
- Sidebar status indicators per chat session (running / completed / failed) ✅
- Invite-code based access control for closed beta ✅
- HTTPS on AWS with Nginx reverse proxy ✅

**Gaps for pilot readiness:**
| Gap | Severity | Estimated fix |
|---|---|---|
| No QC report export (PDF/HTML) — researchers need a document for their methods section | **High** | 3 days — `POST /api/export/qc_report` endpoint |
| No post-run satisfaction survey (exit survey component `run-survey.tsx`) | Medium | 2 days |
| No user documentation (3 short pages: how to query, run, and read QC output) | **High** | 2 days |
| No screen-capture walkthrough video | Medium | 1 day (Founder task) |
| Dev server requires manual restart when routes change (nodemon/tsx --watch not configured) | Low | 0.5 days |

---

### Layer 2: Core AI Analysis Engine

**What is working:**
- Natural language → workflow generation (3–10 second response time) ✅
- 10,595 validated tools across 20 scientific domains ✅
- Drug discovery: 12 phases, complete end-to-end ✅
- RNA-seq: 186 tools, 5 QC profiles, DESeq2/edgeR/limma ✅
- Cryo-EM: standard particle analysis (SPA) and electron tomography (ET), complete ✅
- GOLD/SILVER/BRONZE evidence-graded QC thresholds with published citations ✅
- L0 cache (SubworkflowLibrary) — instant hits for repeated workflow patterns ✅
- L2 tool-plan validation — pre-validates tool list before Nextflow generation ✅
- AutoFix engine — logs analysis, auto-heals common errors, restarts with corrected parameters ✅
- Tiered clarification — collects organism, read type, replicates before generation ✅
- Multi-task (v1) — bullet-list input → sequential workflow generation ✅
- LangGraph 1.1.2 foundation installed for v2 parallel orchestration ✅

**Gaps for pilot readiness:**
| Gap | Severity | Estimated fix |
|---|---|---|
| Some ADMET tools (e.g. DeepPurpose) require installation on partner infrastructure | High | Document as prerequisite; provide install script |
| Multi-task v1 is sequential only — parallel execution requires v2 (Celery dispatch) | Medium | Planned v2 next sprint |
| Clarification dialogue is not yet fully persistent across sessions | Low | Session memory fix |
| GEO/TCGA data connector not yet built (researchers need to upload own data) | Medium | 1 week (TCGAbiolinks + GEOquery wrappers) |

---

### Layer 3: Data Infrastructure Layer

**What is working:**
- AWS deployment: EC2 (t3.medium for dev, scalable for production) ✅
- Redis: running for HTTP sessions, SSE relay, and real-time cost ledger ✅
- PostgreSQL (LTM schema): chat history, workflow runs, pending tasks, telemetry events ✅
- Nginx reverse proxy with HTTPS ✅
- Nextflow execution on AWS Batch: compute scales to job size ✅
- S3: workflow input/output storage ✅
- **Billing system:** Redis-backed real-time cost service (LLM, compute, S3, transfer). Lago subscription management integrated. Per-user quota enforcement. Cohort cost dashboard with p50/p75/p90/p99 spend distribution. ✅
- **Monitoring dashboard:** 7-day error-rate endpoint (HTTP 5xx, workflow timeout, AI errors) with SLA targets. Admin feedback and telemetry dashboard at `/admin/feedback-dashboard`. 30+ analytics event types tracked end-to-end. ✅
- SSE real-time workflow status and Redis pub/sub pipeline event relay ✅

**Security posture:**
- Invite-code access control (closed beta) ✅
- HTTPS enforced; no HTTP in production ✅
- Partner data stays in their S3 / local compute — BioMate does not retain it ✅
- All credentials in environment variables; no secrets in source code ✅
- Billing production guard: `BILLING_DEV_MODE=true` blocked at runtime when `ENV=production` ✅

**Remaining gaps:**
| Gap | Severity | Estimated fix |
|---|---|---|
| No automated nightly CI on live backend | Medium | Configure cron + alert script |
| LTM database not yet migrated to production (SQLite replica in some dev paths) | Medium | Run Drizzle migrations on prod DB |
| Backend process health and Nextflow job-queue visibility not yet surfaced in admin UI | Low | See dedicated dashboard improvement plan |

---

## Part 4: Readiness Summary for the Meeting

### Traffic-Light Assessment

**Platform domains:**

| Direction | Platform State | Pilot Readiness | Key Blocker |
|---|---|---|---|
| **A. Drug Discovery** | 12 phases, 9 QC profiles | 🟢 Ready now | Partner not yet contacted |
| **B. RNA-seq / Precision Med.** | 186 tools, 5 QC profiles | 🟢 Ready now | Texas Children's Hospital — not yet contacted |
| **C. Cryo-EM + AI Structures** | SPA+ET, 23+5 steps | 🟢 Ready now | Partner not yet contacted |
| **D. Single-Cell Perturbation** | 79 tools, 3 QC profiles | 🟡 Partial — scRNA-seq ready; CRISPR screen needs sprint | CRISPR workflow engineering (2 weeks) |
| **E. Multi-Omics (Prot.+Metab.)** | LC-MS cataloged | 🟡 Partial — 1-week LC-MS integration sprint needed | LC-MS-agent wiring; St. Jude not yet contacted |

**Infrastructure:**

| Area | Status | Key Blocker |
|---|---|---|
| **Billing system** | 🟢 Built | Real-time Redis cost ledger, Lago, quota enforcement, cohort dashboard |
| **Monitoring dashboard** | 🟢 Built | Error-rate endpoint + admin feedback/telemetry dashboard; improvements planned |
| **Frontend interface** | 🟡 Mostly ready | Missing: QC report export, user docs, walkthrough video |
| **Data infrastructure** | 🟡 Mostly ready | Missing: nightly CI, prod DB migration |
| **Pilot partners identified** | 🟡 Partial | B (Texas Children's) and E (St. Jude) identified; A, C, D TBD |
| **Core assumptions documented** | 🟢 Done | This document |
| **Exit survey for evidence collection** | 🟢 Built | Required to validate hypotheses |

### Recommended Immediate Actions (Before Partner Outreach)

In priority order:

1. **Build QC report export** (PDF/HTML) — pilot partners need a deliverable document for their methods section. Without this, the pilot cannot demonstrate publication-readiness. *3 days, Engineering.*

2. **Write 3-page user guide** — pilot researchers will not read engineering documentation. Three pages: (1) How to submit a query, (2) How to monitor your workflow, (3) How to read and export your QC report. *Product, 2 days.*

3. **Build exit survey component** (`run-survey.tsx`) — required to validate the five hypotheses above with real user data. *Engineering, 2 days.*

4. **Draft outreach emails** — one per direction. Texas Children's (B) and St. Jude (E) contacts are identified; A, C, D contacts need to be named. Personalise from the template above. *Founder, 1 day.*

5. **Run LC-MS-agent integration sprint** (Direction E prerequisite) — wire `LC-MS-agent` endpoints through the Galaxy API proxy so proteomics workflows are accessible from the chat interface. *Engineering, 1 week. Schedule before St. Jude pilot begins.*

7. **Record 3-minute walkthrough video** — send with outreach email. Show: type a query → workflow generates → execution runs → QC gate result → export report. *Founder, 1 day after QC export is built.*

8. **Improve backend monitoring** (recommended before pilot) — surface Nextflow job-queue depth, AutoFix event rates, and process health in the admin dashboard. See the dedicated dashboard improvement plan. *Engineering, 5.5 days total.*

### What BioMate Can Demonstrate Today (Without Any Additional Development)

- Live query → Nextflow workflow generated in <10 seconds
- Workflow execution on AWS with real-time status updates in the browser
- QC gate triggers (with scientific rationale and GOLD/SILVER/BRONZE evidence levels)
- AutoFix — automatic log analysis and parameter correction on failure
- Run Manager — concurrent workflow monitoring
- Drug discovery: ADMET filtering, molecular docking, Phase I NCA
- RNA-seq: FastQC → STAR → DESeq2 → pathway enrichment
- Cryo-EM: CryoSPARC standard SPA pipeline

---

## Part 5: Questions the Partner Will Likely Ask

*Prepared answers for the meeting:*

**"How does BioMate differ from ChatGPT or other AI tools I can use for bioinformatics?"**
> BioMate executes the workflow — it does not suggest steps. Generic LLMs generate text that looks like a pipeline; BioMate runs validated Nextflow code against real data and monitors it in real time. Every tool in our catalog is validated (10,595 tools vs. ChatGPT's hallucinated suggestions). Every QC threshold is cited to a published paper. The result is a reproducible, auditable run log, not a text suggestion.

**"What data security measures are in place?"**
> Closed beta with invite-code access. All traffic encrypted via HTTPS. Partner data stays in the partner's S3 bucket or local compute — BioMate does not copy or retain research data. A data use agreement will be signed before any pilot analysis.

**"Can I use my own data or do I need to use public datasets?"**
> Both. Public datasets (GEO, TCGA, EMDB) are the easiest start — BioMate can pull them directly. For your own data, we upload to a secure S3 bucket under your control. A GEO/TCGA connector is on the roadmap for auto-import.

**"What does the pilot cost me?"**
> Nothing. BioMate covers compute costs for the pilot period. We ask for one researcher's time (~2 hours/week) and written feedback at the end.

**"How reproducible are the results?"**
> Every workflow run produces a full audit log: which tools were selected and why, which QC thresholds were applied with their source citations, and which parameters were used. This log is sufficient for inclusion in a methods section. Reproducibility is enforced at the Nextflow DSL2 level — the same workflow.nf file produces the same result on the same data.

**"What happens if the pipeline fails?"**
> The AutoFix engine monitors execution logs in real time, diagnoses the failure category (resource, parameter, data format, environment), applies a correction, and restarts automatically. For failures it cannot correct, it surfaces a specific error message with a suggested fix for the researcher to review.

---

*Document prepared by: BioMate Engineering & Product Team*
*Date: March 2026*
*For partner meeting use only — do not distribute without review*
