# Supplementary — BioMate Catalog Anatomy (self-statistics)

Quantitative anatomy of the BioMate catalog, computed directly from the `galaxy_ai_tools.db` snapshot (2026-08-17) and the workflow source tree. Every number is a query on committed data; the queries are listed in §A9 for reproducibility. This supplement answers "what *is* the catalog" — its size, structure, step/tool composition, semantic organization, enrichment, and code volume.

## A1. Headline

| Quantity | Value |
|---|---|
| Executable workflows | **4,057** |
| Biological domains | **39** |
| Total workflow steps | **19,956** |
| Distinct step *labels* (free-text; not canonical ops — §A4) | **10,195** |
| Indexed tools (tool library) | **12,301** |
| Distinct tools referenced by workflows | 3,385 |
| Canonical semantic phases (runtime) | **6** |
| Domain-specific phase definitions (design) | 44 (36 distinct names) |
| Workflow-definition code volume | **25.2 MB** JSON / **855,580 LOC** across 4,498 `.nf` files |
| Tool knowledge / enrichment records | 4,141 knowledge + 9,656 compatibility |

## A2. Workflow catalog — provenance and readiness

| Property | Count | % of 4,057 |
|---|---|---|
| Executable | 4,012 | 98.9% |
| Carries a container image | 3,669 | 90.4% |
| Enriched annotation (`annotation_v2`) | 3,233 | 79.7% |
| Machine-readable parameter schema | 3,058 | 75.4% |
| Carries real-execution evidence (`real_exec_status`) | 2,332 | 57.5% |
| Step-level metadata | 3,152 | 77.7% |
| Visualization tools attached | 2,293 | 56.5% |
| QC-step annotation | 430 | 10.6% |

**By format:** Nextflow 3,510 · Bioconductor-NF 535 · other (R/Galaxy/Python) 12.
**By source:** Bioconductor 3,315 · Biomni-Nextflow 258 · nf-core 230 · nf-core subworkflows 93 · Nextflow 64 · BioMate-native 82.

## A3. Domain distribution (top 12 of 39)

| Domain | Workflows | | Domain | Workflows |
|---|---|---|---|---|
| transcriptomics | 1,693 | | drug_discovery | 122 |
| genomics | 750 | | systems_biology | 108 |
| epigenomics | 262 | | single_cell | 95 |
| proteomics | 182 | | imaging | 77 |
| variant_calling | 181 | | metagenomics | 75 |
| general (utilities) | 143 | | metabolomics | 57 |

(27 further domains hold the remaining ≈360 workflows; full per-domain census released with the snapshot.) See **Fig. An-1** (workflows-by-domain).

## A4. Step anatomy — how workflows are composed

| Statistic | Value |
|---|---|
| Total steps across catalog | 19,956 |
| Mean steps / workflow | 4.9 |
| Median steps / workflow | 3 |
| Interquartile (p25–p75) | 1 – 6 |
| p90 | 9 |
| Max (deepest workflow) | 222 |
| **Distinct step *labels*** (free-text) | **10,195** (11,635 named instances) |

*The 10,195 count is distinct free-text step **labels** (natural-language descriptions), not a canonical operation vocabulary: light normalization (case/whitespace/punctuation) merges only ~4, so the labels are genuinely distinct strings, but many are paraphrases of the same operation (e.g. "read user input files" vs "read user input" vs "read user inputs"). It should be read as the diversity of the natural-language step descriptions, not as 10,195 unique canonical steps.* Most-reused labels are I/O boilerplate the router standardises — "read user input files" (227×), "save outputs" (118×) — though such I/O labels are only ≈9% of all named instances, confirming a common ingest/emit scaffold around domain-specific cores. See **Fig. An-2** (steps-per-workflow distribution).

## A5. Tool composition per workflow

| Statistic | Value |
|---|---|
| Workflows with an explicit tool list | 2,524 |
| Mean tools / workflow | 2.7 |
| Median tools / workflow | 2 |
| Max tools / workflow | 16 |
| Distinct tools referenced across all workflows | 3,385 |

## A6. Semantic phase organization (the "information-flow" layer)

Two layers of phase semantics organise the catalog:

**Runtime (applied to workflows).** Every step in the 3,152 step-annotated workflows is grouped into one of **6 canonical phases**, in flow order: **input & preparation → QC & filtering → core analysis → annotation & interpretation → visualization & output → output & reporting**. This is the layer surfaced as phase cards in the workflow panel.

**Design (domain templates).** `domain_workflow_patterns.py` encodes **44 domain-specific `WorkflowPhase` definitions** (36 distinct names) across domain patterns, each with typical tools and an early/middle/late position — the biologically-meaningful phase best-practices from which runtime grouping draws. Supporting structures: **70 workflow chains** and **24 phase-rationale** records.

## A7. Tool library (12,301) — knowledge and enrichment coverage

| Property | Count | % of 12,301 |
|---|---|---|
| Scientific-context (v1) | 10,238 | 83.2% |
| **Scientific-context v2 (deep enrichment)** | 3,176 | **25.8%** |
| Literature citations | 7,954 | 64.7% |
| Parameter specifications | 8,185 | 66.5% |
| Usage guide | 3,446 | 28.0% |
| Dedicated knowledge record (`tool_knowledge`) | 4,141 | — |
| Compatibility record (`tool_compatibility`) | 9,656 | — |

**By language:** CLI 7,248 · Nextflow 3,463 · R 659 · Python 497 · other 434.
The v2-enrichment coverage (25.8%) is the catalog's principal *known* quality gap — the enrichment frontier, not a data error. See **Fig. An-3** (enrichment coverage).

## A8. Code volume

| Corpus | Volume |
|---|---|
| Workflow definitions (`workflow_json`) | 25.2 MB · mean 6,216 chars · median 5,251 · max 169,774 |
| Tool text (raw + help) | 26.8 MB across 10,531 tools · mean 2,544 chars |
| Workflow source files (`.nf`) | **4,498 files · 855,580 LOC** |

## A9. How audit traces are formed

Provenance is produced in-line during execution, not reconstructed afterward. A single in-process hook (`qc_trace_monitor`) intercepts each step's structured output and routes its metrics through the step's domain-specific gate evaluator. On a threshold decision the hook emits one record carrying the **failing metric, the threshold, the threshold's citation (DOI), its evidence grade** (GOLD = verbatim in a peer-reviewed/regulatory source; SILVER = attributed community convention; BRONZE = disclosed heuristic), the **tier/approver**, and the outcome (**PASS / ADVISORY / HALT**). Records are appended to a portable per-run **JSONL audit trail** whose fields are aligned to 21 CFR Part 11 (threshold · evidence-DOI · grade · approver · timestamp); 117 grade-bearing gates across 35 domains back these decisions. A separate compliance channel logs any detected PHI event **hash-only** (event type, matched-pattern type, rule name — no plaintext). One trail spans the full run — interpret → route → execute → QC → report — so a reviewer can trace each governed decision to the threshold, its source, and its grade. *Scope note: an append-only, provenance-carrying audit trail is not unique (Seqera/GAMP5, DNAnexus/HIPAA carry mature trails); what is distinctive is the **evidence-grade + threshold-provenance + override-approver** triple those data models do not carry (§5.3 main text).*

## A10. Execution model — local vs cloud, and the resource-usage difference

BioMate routes work to one of two execution paths by task footprint:

| Path | What runs here | Provisioning | Resource metering |
|---|---|---|---|
| **Cloud — AWS Batch** | validated multi-step pipelines (RNA-seq, WGS/sarek, cryo-EM, docking, MD, PBPK) | containerised jobs on `biomate-nextflow-queue`; per-job vCPU/GPU/memory allocation | **fully per-resource**: `batch_vcpu_seconds` ($0.05/vCPU-hr), `batch_gpu_seconds`, `batch_memory_gb_sec`, `s3_storage_gb_hours` ($0.023/GB-month) — emitted per job via EventBridge → billing Lambda → real-time ledger |
| **Backend-local — `run_code`** | ad-hoc, short analysis (a single statistical test, file parsing, a small transform) | backend **subprocess** execution (process-level isolation; *not* a hardened/security sandbox); **no cloud job provisioned** | **no per-resource compute meter** — only LLM tokens ($0.25/1M input) are billed |

The consequence for resource usage is that the *heavy, reproducible, containerised* work carries a full per-resource cloud footprint (vCPU-, GPU-, memory-, storage-hours, metered per job), while *lightweight ad-hoc* work runs backend-local at LLM-token cost only — the router matches the resource footprint to the task rather than sending every request to the cloud. This is also why the engine-free governance decisions (routing, QC gating) carry zero compute cost (§ model-invariance): they never enter either execution path.

## A11. Reproducibility — queries

All counts above are single queries on `backend/database/galaxy_ai_tools.db` (snapshot 2026-08-17). Examples: workflows `SELECT COUNT(*) FROM workflows`; domains `SELECT COUNT(DISTINCT domain) FROM workflows`; steps `SELECT SUM(step_count) FROM workflows`; enrichment `SELECT COUNT(*) FROM tools WHERE scientific_context_v2 IS NOT NULL AND scientific_context_v2!=''`; distinct steps and phases are parsed from `step_metadata` (JSON) as in the anatomy script (released with the snapshot). The database is gitignored and distributed as a dated snapshot; the live catalog may be larger at read time.

*Figures An-1 (domains), An-2 (steps distribution), An-3 (enrichment coverage) generated by `docs/figures/anatomy/make_anatomy_figs.py`.*
