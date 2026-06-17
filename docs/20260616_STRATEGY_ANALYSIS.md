# BioMate Strategy Analysis — Clients · Competitors · Profitability · CRO Positioning

Date: 2026-06-16
Author: drafted from in-repo evidence + your todo_0615.md §2 selection.
**Status**: first-draft skeleton. Sections marked `[NEEDS-EXTERNAL]` require
website / pricing / interview research outside the repo before they're
defensible to a customer or partner.

---

## A. Clients — services we can deliver today

Inventory from the workflow catalog (`workflow_chains` 60 chains + ~14,000
indexed sub-workflows). Grouped by buyer persona to make the services
list customer-facing:

### A.1 Bench biologist / wet-lab scientist
*Buyer signals*: needs RNA-seq / single-cell / methylation / variant pipelines
without writing code. Today usually goes to Galaxy / nf-core CLI / a bioinformatics core.

| Service we deliver | Backed by |
|---|---|
| Bulk RNA-seq DE end-to-end (counts → DESeq2 → GO) | `bulk_rnaseq_consensus_de_bioc` chain + Wave 1-2 citations |
| Single-cell condition DE the statistically correct way (pseudobulk) | `scrna_pseudobulk_de_bioc` chain (id 60) |
| 450k methylation → DMRs | `methylation_450k_array_analysis` chain |
| Variant calling + annotation | sarek + bioc_variant_annotation chains |
| ATAC / ChIP / CUT&Tag chromatin | `cutandtag_chromatin_analysis` chain |
| Spatial transcriptomics | `geomx_spatial_transcriptomics` chain |

*Positioning*: cheaper + faster than hiring a postdoc consultant, more
honest than ChatGPT-with-a-bioinformatics-prompt (we cite the paper for
every method choice via the new `(why?)` anchor + qc_evidence.yaml).

### A.2 Drug discovery / preclinical pharmacology team
*Buyer signals*: ADMET prediction, PBPK simulations, docking screens, target
tractability. Today uses Schrödinger / Simulations Plus / Certara.

| Service | Backed by |
|---|---|
| ADMET property prediction + filtering | `drug_discovery_admet_gated_screening` chain |
| Target → lead progression (tractability + docking + ADMET) | `target_to_lead_full` (6 steps) |
| ADMET → CiPA cardiac safety | `admet_to_cipa_cardiac` chain |
| PBPK → tumor TGI | `pbpk_to_tumor_tgi` chain |
| CYP450 DDI screening | `cyp450_ddi_chain` |
| Phase 2 dose justification | `phase2_dose_justification_chain` |
| mRNA codon optimization | `mrna_codon_optimization_chain` |

*Positioning*: workflow-grade pricing (per-run, not per-seat license)
vs. the $100K+/seat/yr Schrödinger model. Compliance with 21 CFR Part 11
audit trail (via qc-events + the workflow_phase_rationale table).

### A.3 Clinical operations / pharmacometrician
*Buyer signals*: nlmixr2 popPK, allometric scaling, IND §2.6.1 narrative
generation. Today uses Monolix / NONMEM / consultants.

| Service | Backed by |
|---|---|
| Population PK with nlmixr2 | qc_evidence `nlmixr2_poppk` (3 gates, cited) |
| Allometric scaling | qc_evidence `allometric` (1 gate, cited) |
| First-in-human dose with IVIVE | qc_evidence `ivive` (2 gates, cited) |
| IND §2.6.1 prose generation | shipped Apr 2026 — `_llm_narrative()` |

*Positioning*: prose with citation; methodology audit-trail; reproducible
re-runs cost <$1.

### A.4 CRO / biotech IT buyer (the "AI CRO" play, see §D)
*Buyer signals*: wants to white-label compute platform, not buy seat
licenses. Today builds in-house.

| Service | Backed by |
|---|---|
| Multi-tenant Lago billing per workflow | Lago + Java billing service (deployed Mar 2026) |
| Compliance audit trail per run | qc-events + Wave 1-2 citation infrastructure |
| Cross-org adapter retrain (Lane B3) | regulatory_training_routes (deployed) |

`[NEEDS-EXTERNAL]` — pricing benchmarks vs Schrödinger/Genedata/SeaBio/Tessera.

---

## B. Competitors — connectors + challenges

Per your direction we are building connectors. Inventory of who we connect
TO vs compete WITH, from evidence in the repo:

### B.1 We already integrate with (connector built or planned)

| Provider | What | Connector state |
|---|---|---|
| **nf-core** | community pipelines (rnaseq, sarek, scrnaseq, cutandrun, …) | ~80 chain steps reference `nf-core/*` — already a primary execution backend |
| **Bioconductor** | R/Bioc packages (DESeq2, minfi, scran, SingleR, …) | curated chain templates + 24 cited rationales (Wave 1-2 + L) |
| **Galaxy** | workflow engine + history | embedded — Galaxy is the substrate |
| **AWS Batch** | compute backend | primary execution target |
| **CryoSPARC** | cryo-EM workflows | `gpcr_spa_cryo_em_pipeline` chain |
| **Lago + Java billing** | metering + invoicing | deployed Mar 2026 |
| **RStudio / Jupyter / CellxGene** | interactive launcher per output | shipped in design (REQUEST_ADD_INTERACTIVE_PANEL.md) |

### B.2 Direct competitors (LLM-driven scientific assistants)

| Competitor | Their angle | Our differentiator | Gap |
|---|---|---|---|
| **Biomni** (Stanford) | LLM-driven biomedical agent, ~150 tools, ~6 use cases | We have **2,455 indexed workflows + 60 curated chains**, run real chains on AWS Batch (not just code snippets), publish billing receipts | They have name recognition + open science narrative. We need a head-to-head benchmark blog (todo_0615.md §1.b). |
| **The Nature 3-co-scientist papers** (GenoSphere, BioMedLM, etc) | research-paper assistants | Not yet a head-to-head story | `[NEEDS-EXTERNAL]` — need paper deep-read + a benchmark on shared tasks |
| **OpenAI / Anthropic + bioinformatics prompt** | general LLM with users wiring own data | We have curated chains, QC gates, citations | They have brand + price floor. We need to show why a curated chain beats ad-hoc prompting on reproducibility + cost. |
| **GitHub Copilot / Cursor for bio** | code-completion for data scripts | Different category — we run pipelines, they help write them | None — orthogonal |
| **Schrödinger / Simulations Plus / Certara** | per-seat licensed pharma platforms | Per-workflow pricing + open-source backend + LLM interface | They have validated science + decades of pharma trust. We need the per-domain audit (todo §2.a). |

### B.3 Connector-build challenges

| Challenge | Risk | Mitigation in-flight |
|---|---|---|
| nf-core pipeline-version drift breaks chain steps | high — workflow_chains has 2 chain steps pinned, 86 unpinned | `pin_bioc_chain_workflow_ids.py` migration (this session) — extend to all 60 chains |
| Galaxy schema migrations break inter-version chain history | high — alembic 204367c6a604 already in play | invocation_id → run_id helper (Stage 2d, just merged) |
| CryoSPARC licensing per-org makes multi-tenant SaaS awkward | medium | license-key passthrough (already shipped) |
| LLM provider lockin (Anthropic Claude Opus for narrator) | medium — we'd pay 10x to swap to GPT-4 mid-conversation | `[NEEDS-EXTERNAL]` — cost model + Gemini-3-flash fallback design |

---

## C. Profitability stratification — heavy vs small data work

Margin model (rough, from billing event sample on dev):

### C.1 Per-run cost ↔ chargeable price ↔ margin

| Workflow class | Compute cost (Batch) | Chargeable | Margin |
|---|---|---|---|
| **Small data** (count matrix DE, methylation IDAT, allometric, NCA-PK) | $0.10–$1 (1–4 vCPU-hr) | $5–$20 — knowledge value not compute cost | **>90% margin** |
| **Medium** (bulk RNA-seq from FASTQ, scRNA cellranger, sarek germline) | $5–$50 (4 vCPU-hr to 8 GPU-hr) | $30–$200 | 50–70% margin |
| **Heavy** (cryo-EM SPA, AlphaFold-Multimer, MD trajectories, large WGS cohorts) | $50–$500+ (GPU-hours, dedicated instance) | $200–$2000 | 30–50% margin, with capacity-constraint risk |

### C.2 Stratification recommendation

| Tier | Examples | Pricing model | Rationale |
|---|---|---|---|
| **Tier 1 (free + freemium)** | small-data DE, methylation, NCA, ADMET single-compound | usage cap (e.g. 10/mo free), $10/run after | Acquisition channel — zero compute cost on our end |
| **Tier 2 (per-run premium)** | full bioc chains, drug-discovery chains, IND prose | per-run $30–$200 with bundled storage + interactive launcher hour | Highest margin; what brings repeat usage |
| **Tier 3 (capacity-committed)** | cryo-EM SPA, MD, AF-multimer, WGS cohorts | monthly committed-spend + overage at marginal cost | Margin lower but stickiness highest; enterprise/CRO sells |

**Key insight**: small data is more profitable per-dollar-of-revenue than
heavy data, because we charge for *the answer* (DE table, DMR list, PBPK
prediction), not the compute. The "small data don't need extra parallel
computation" observation in your todo is right — and it's where we should
push freemium acquisition.

`[NEEDS-EXTERNAL]` — actual margin numbers need Lago invoice export + AWS
Cost Explorer reconciliation over 3 months.

---

## D. AI CRO positioning — what we are, what we're missing

### D.1 What makes us a credible "AI CRO" today

1. **End-to-end audit trail per run** — qc-events + `workflow_phase_rationale`
   table (this session) + chain-of-custody columns in the rationale_registry.
   This is the 21 CFR Part 11 / GLP-readiness story competitors don't have.
2. **Curated chains with citations** — every DE result, every DMR call,
   every ADMET threshold cites the paper that justifies the choice
   (qc_evidence.yaml has 73 gate-level DOIs, 24 are wired through
   the new `(why?)` anchor — committed this session).
3. **Reproducible re-runs at near-zero cost** — pinned `workflow_id` per
   chain step (this session) + Nextflow `-resume` + S3 work_dir
   means a re-run for an auditor costs cents.
4. **Multi-tenant billing + quota gating** — Lago + Java billing
   shipped Mar 2026.
5. **Methodology prose generation** — `_llm_narrative()` for §2.6.1 IND
   shipped Apr 2026; same machinery extensible to §2.7.x / §5.x.

### D.2 What's missing for AI CRO sole-source

| Missing | Effort | Source |
|---|---|---|
| **Wet-lab partnership** — molecule synthesis, in-vitro assays, animal studies. Computational CRO ≠ full CRO. | Out of repo — needs commercial partnership (LabCorp/Charles River/Wuxi). | strategic |
| **GxP-grade SOPs + 21 CFR Part 11 audit pass** — we have the trail; we don't have an inspector's stamp | 6–9 months + quality lead + auditor engagement | strategic |
| **Per-domain expert review** of the 60 chains + ~150 rationale_ids | per todo §2.d — the scientific-lead-per-domain answer | this session (gap tracker + mapping yaml deliverables 1+4) |
| **Real-time CRO project tracking** (timesheet, deliverable PDFs, client portal) | medium | not yet started |
| **Insurance** — E&O for computational predictions used in IND submissions | external | TBD |
| **Reference clients** — 2–3 named biotech case studies with publishable results | sales | TBD |

### D.3 Stand-alone vs. CRO partnership

Recommendation: **stand-alone for computational deliverables, partner for
wet-lab**. Specifically:

| Deliverable | Stand-alone or partner |
|---|---|
| ADMET prediction package | stand-alone |
| Bulk RNA-seq DE + GO + manuscript prose | stand-alone |
| PBPK + clinical trial Phase 2 sim + IND §2.6 prose | stand-alone (with QA cert) |
| Molecule synthesis + in-vitro hERG follow-up | partner (Charles River / Eurofins) |
| GLP toxicology animal study | partner (Charles River / Inotiv) |
| GMP CMC bioassay | partner (LabCorp / Wuxi) |

White-label angle: we power their computational layer; they handle wet
work. Lower customer-acquisition cost; their existing client base
becomes our funnel.

`[NEEDS-EXTERNAL]` — competitive intel on 3–5 mid-size biotech CROs
considering an AI add-on (CRO sales-cycle data outside repo).

---

## Sign-off checklist

| Section | Defensible to a customer today? |
|---|---|
| A — services list | Yes, sourced from real workflow_chains rows |
| B.1 — connectors | Yes |
| B.2 — direct competitors | Partial — needs B.3 [NEEDS-EXTERNAL] items resolved before publishing |
| B.3 — challenges | Yes |
| C — profitability tiers | Margins are estimates; Lago invoice export + AWS Cost Explorer needed for exact numbers |
| D.1 — CRO credentials we have | Yes |
| D.2 — missing pieces | Yes |
| D.3 — partner vs stand-alone | Defensible recommendation; specific partner names depend on commercial conversations |

## Next concrete actions

1. **Lago invoice export + AWS Cost Explorer reconciliation** over the
   last 3 months — closes the margin numbers in §C.
2. **Head-to-head benchmark vs Biomni + the 3 Nature co-scientists** on
   the 13 BiomniEval1 tasks (already shipped) + a public bioc DE task.
   Output: a blog per todo_0615.md §1.b.
3. **Schedule 3 customer-discovery calls** in each of A.1 / A.2 / A.3 —
   validate the services list maps to their pain.
4. **Scientific-lead recruiting per domain** (todo §1, §2.d) — the
   gap_tracker.md from this session is their schedulable work.
