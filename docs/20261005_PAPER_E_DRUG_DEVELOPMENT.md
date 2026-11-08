# BioMate: An Execution-First, QC-Governed Platform for Reproducible In-Silico Drug Development

**First draft — platform / methods paper.** 2026-10-05.

**Target venue:** *Journal of Chemical Information and Modeling* (JCIM).
Alternatives: *Journal of Cheminformatics*; *Bioinformatics* (Applications Note / software);
*Drug Discovery Today* (perspective framing, lower methods depth).

**Authors:** `[AUTHORS TBD]` — not invented. Affiliations and ORCIDs TBD.

**Keywords:** in-silico drug development; ADMET; QC governance; reproducibility; workflow execution;
hERG; cardiotoxicity; auto-remediation; provenance.

> **Framing (read before editing).** This manuscript makes a *governance / reproducibility* claim, not a
> *discovery* claim. The thesis is: **BioMate is an execution-first, QC-governed platform that delivers
> trustworthy, auditable in-silico drug-development automation** — its scientific **ADMET QC auto-loop**
> fires on a scientifically-unsafe candidate with a *cited* threshold and proposes a *grounded* parameter
> remediation over an *actually-executed* pipeline, something general LLM / code-sandbox agents do not
> demonstrate. The story is **"you can trust the result — it catches the unsafe candidate and tells you
> why, with a citation,"** never "we discovered a drug." No wet-lab validation is claimed anywhere.

---

## Abstract

In-silico drug development is increasingly automated by large-language-model (LLM) agents and
code-sandbox systems, but these tools generate answers rather than execute validated pipelines, and they
offer no scientific quality-control (QC) layer that can flag an unsafe candidate and justify the flag
against the literature. We present **BioMate**, a chat-driven platform that routes a scientist's request
to a curated catalog of executable Nextflow / nf-core / Bioconductor workflows (**4,209 workflows as of
2026-10-04 across ~36 domains, indexed over 12,312 tools**; **1,092 carry clean end-to-end
real-execution evidence**), runs them on managed AWS Batch compute, and governs the result with a
**scientific QC auto-loop**. The QC auto-loop evaluates workflow outputs against literature-anchored
thresholds; on a failing gate it emits a cited halt and a **deterministic, grounded parameter
remediation**. We demonstrate the mechanism on a live, committed ADMET screen: a two-compound panel
(aspirin + terfenadine) run on AWS Batch tripped a GOLD-tier hERG cardiotoxicity gate at a model-estimated
IC50 of 0.012 µM — below the 1.0 µM high-risk threshold (Sanguinetti & Tristani-Firouzi 2006; FDA E14) —
plus a high-DILI gate (DILIrank; Chen 2016), and the system proposed tightening the developability envelope
(logP max 5.0 → ≤4.0; MW max 500 → 400 Da). A control run on a safe panel produced empty gates, showing the
gate discriminates rather than always-firing. We describe the surrounding drug-development workflow suite
(docking, QSAR, generative design, binding free energy, PBPK, non-compartmental PK, Bayesian
dose-escalation) and report honest benchmark numbers, including a same-item PBPK within-2-fold accuracy of
**0.200** (not a previously-cited cross-harness figure). **All ADMET values are Chemprop / ADMET-AI model
estimates requiring experimental validation; the remediation is reactive / advisory (a suggestion plus a
server-sent parameter diff), not an autonomous closed-loop restart.** BioMate's contribution is
reproducible, auditable execution with a scientific QC gate — a trust layer that general agents do not
provide.

---

## 1. Introduction — the trust gap in automated in-silico drug development

Automated drug-development reasoning has advanced rapidly: hypothesis-and-literature agents (Google AI
co-scientist, FutureHouse/Edison Kosmos, Anthropic Claude for Life Sciences, OpenAI for Science),
code-sandbox generalists (Biomni), and closed vertically-integrated pharma platforms (Recursion/LOWE,
Insilico Pharma.AI, Isomorphic, Genentech) each occupy part of the landscape
(`internal/marketing-research/competitors_ai_agents.md`). What is missing is a **trust layer**: a product
to which a scientist can submit their own SMILES or structures, have a *validated* pipeline executed on
managed compute, and receive a result that is **governed** — i.e., checked against scientific safety
criteria, with any failure flagged, cited, and accompanied by a concrete corrective action.

The gap matters specifically for drug development, where the cost of trusting a wrong answer is high. A
naive screening pipeline that silently reports ADMET predictions will happily pass a compound with a
known cardiotoxic (hERG) liability; the scientist has no automated signal that the candidate is unsafe,
nor a literature anchor for why. LLM/code-sandbox agents compound this: they *generate* a plausible
answer token-by-token with no execution provenance and no QC gate, so a confident but wrong toxicity
estimate is indistinguishable from a correct one.

This paper argues that the value layer for automated drug development is **execution + reproducibility +
governance**, not raw model reasoning, and presents BioMate as a platform built around that thesis. Our
contributions:

1. A **catalog-routed execution architecture** that turns "generate an answer" into "retrieve and run the
   validated workflow," with recorded parameters, versions and outputs (Section 2).
2. A **scientific QC auto-loop** that evaluates executed workflow outputs against literature-anchored
   gates and emits a cited halt plus a deterministic, grounded parameter remediation (Section 2.3).
3. A **live, fully-committed ADMET governance case study** (hERG + DILI gates firing on a real AWS Batch
   run, with a discriminating control) demonstrating the mechanism end-to-end (Section 3).
4. A **drug-development workflow suite** and **honest benchmark characterization**, including corrections
   of previously-overstated numbers (Sections 4–5).

We make no discovery claim and no wet-lab validation claim. Every predicted property reported here is a
model estimate.

---

## 2. Architecture: a catalog + a scientific QC auto-loop

### 2.1 Catalog and routing

BioMate indexes **4,209 workflows (as of 2026-10-04) across ~36 curated domains (42 raw domain tags),
over 12,312 tools** (`docs/20261004_CATALOG_COUNT_RECONCILIATION.md`, queried directly from
`backend/database/galaxy_ai_tools.db`). The catalog is dominated by Bioconductor (3,326), with nf-core
and Nextflow subworkflow families layered on top. The drug-relevant domains include **drug_discovery
(200 workflows)** and **pharmacology (39 workflows)**; transcriptomics, genomics and variant-calling
provide the upstream target-biology context.

**Validated subset (stated separately, never conflated with the catalog count):** **1,092 workflows carry
clean real-execution evidence** (`real_exec_status IN ('ok','ok_warnings')`: 690 strictly `ok` + 402
`ok_warnings`); 1,791 have produced some output. The catalog count (4,209) is a breadth figure and is not
presented as the validated/tested number.

> **Count reconciliation (required).** Earlier internal and external materials cited the catalog three
> ways — 2,455/34 (stale, in CLAUDE.md), 4,017/36 (MCP server string; on-prem manuscript), and 4,200/36
> (rounded snapshot). The canonical figures are **4,209 total / ~36 domains / 12,312 tools; 1,092
> validated**. The internal RealBio leaderboard (`evaluation/datasets/public_export/leaderboard.md`) still
> prints stale counts ("2,400+/34 domains," "4,057-workflow catalog") in its footnotes — **FLAG: reconcile
> those before external use.**

A chat request is classified (intent → domain → workflow) and routed to a matching catalog workflow; a
frontier LLM handles free-text extraction (SMILES, structures) and ambiguous enum selection, while
rule-based inference handles deterministic mappings. The routing / retrieval layer, not the LLM, is the
differentiator: on an internal routing benchmark BioMate reaches **0.965** (n=200, 95% CI [0.930, 0.983]),
and handing a frontier LLM the same catalog lifts its routing by ~35–40 pp into the same band
(`leaderboard.md`).

### 2.2 Execution on managed compute

Matched workflows execute on **AWS Batch** as real Nextflow / nf-core / Bioconductor pipelines, with run
provenance (run IDs, invocation IDs, parameters, S3 outputs) recorded. This is a product capability, not
a sandbox: the same request yields a pinned, versioned, re-runnable pipeline with recorded outputs. In a
drug-development batch-hardening pass, **24/24 drug-development workflows passed end-to-end on AWS Batch**
(`docs/20260418_DRUG_DEV_BATCH_WORKFLOWS_24_OF_24_PASSING.md`, IDs 12861–12884), after resolving a chain
of seven real infrastructure/code bugs (compute-environment AMI, Groovy GString escaping, NumPy 2.0 API).

### 2.3 The scientific QC auto-loop

The QC auto-loop is the governance mechanism. For the ADMET domain
(`backend/experiments/admet_autoloop/`, `docs/20260417_ADMET_AUTOLOOP_ARCHITECTURE.md`), it:

1. **Evaluates** executed workflow outputs (`toxicity_report.json`: hERG IC50, DILI risk/probability, Ames)
   against literature-anchored gates. Gate thresholds derive from existing BioMate infrastructure, not from
   benchmark tuning — e.g. hERG safety threshold from ICH S7B (`assay_ingestion.py`), DILI boundary from
   Lammert 2010, Ames from Kazius 2005 structural alerts.
2. **Classifies** each gate as HALT / ADVISORY / PASS, with an evidence tier (GOLD/SILVER) and a citation
   string attached to the gate message.
3. **Remediates** deterministically: a `param_tuner` maps each HALT to a grounded parameter change (e.g.
   hERG HALT → tighten logP/MW per an Aronov-2008-style QSAR inversion; DILI HALT → logP max → 4.0, MW max
   → 400 per the Lammert boundary).

The auto-loop orchestrator is domain-generic (it mirrors the cryo-EM auto-loop; only the phase list and
gate/tuner modules are domain-specific), and the ADMET implementation ships **24/24 passing unit tests**
across gate logic, remediation rules, orchestration, audit logging and multi-gate escalation scenarios.

> **Honesty — what the auto-loop is and is not.** The loop is **reactive / advisory**. On a failing gate
> it emits `autoloop_gate_results` + `autoloop_update` server-sent events (carrying the parameter diff) and
> stores the suggestion keyed by invocation ID; the actual re-run is a **separate, deliberate call**, not a
> fully autonomous closed-loop restart. It *recommends* the fix and shows the was→now diff; the human
> decides to re-run. (`docs/20261004_AUTOLOOP_LIVE_PROOF.md`.)

---

## 3. Hero case study (Tier-3): BioMate catches a cardiotoxic candidate and justifies it

This is the flagship governance demonstration. Every value traces to a committed run; **no simulated
numbers.** Sources: `docs/20261004_HERO_A_CASE_STUDY.md`, `docs/20261004_AUTOLOOP_LIVE_PROOF.md`, and the
raw S3 outputs saved at `docs/autoloop_live_proof_20261004/{qc_metrics.json,toxicity_report.json}`.

### 3.1 The screen (real AWS Batch run)

A two-compound ADMET/developability panel was submitted in plain English and executed on AWS Batch:

- **Run:** `d0ff684b-fd91-4e6f-ba0a-ea136b427700` (invocation `631ab616-…`), workflow *Predict ADMET
  Properties (AI)* (`nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf`),
  `ADMET_model_type = MPNN`, `admet_shard_size = 25`. Status **succeeded**, returncode 0, **292 s**.
- **Inputs:** `smiles_list = [aspirin, terfenadine]` — aspirin as a hERG-safe control, terfenadine as a
  known hERG liability (the antihistamine withdrawn for QT prolongation / Torsade de Pointes).

### 3.2 The hero beat — the QC gate HALTS, live, with citations

The durable run record `qc_gates` (saved to S3, reproduced in `20261004_AUTOLOOP_LIVE_PROOF.md`) contains
two firing GOLD-tier gates:

| Gate | Value | Threshold | Verdict | Citation (in the gate message) |
|---|---|---|---|---|
| `herg_ic50_uM` | **0.012** µM | 1.0 µM (`<`) | **[GOLD] HALT** | Sanguinetti & Tristani-Firouzi 2006; FDA E14 — predicts QT prolongation / TdP |
| `dili_risk` | **high** | low (`!=`) | **[GOLD] HALT** | DILIrank; Chen et al. 2016 — hepatotoxicity investigation required |

Per-compound ground truth from the run's S3 `toxicity_report.json`
(`docs/autoloop_live_proof_20261004/toxicity_report.json`): terfenadine logP 7.01, MW 499.7, **hERG IC50
0.0124 µM, hERG_prob 0.974**; aspirin hERG-safe (IC50 10000 µM, hERG_prob 0.003) but DILI_prob 0.855
(high). Panel aggregation is worst-compound-in-panel: terfenadine drives the hERG halt, aspirin drives the
DILI halt. Evidence tier recorded as `GOLD-Redfern2003 / SILVER-Kazius2005 / SILVER-Mulliner2016` with a
full citation string in `qc_metrics.json`.

### 3.3 The grounded remediation (was → now)

For the two halting gates, the deterministic `param_tuner.remediate()` output tightens the developability
envelope:

| Parameter | Was (default) | Now (remediated) | Basis |
|---|---:|---:|---|
| `logp_max` | 5.0 | **≤ 4.0** | hERG QSAR inversion capped at the Lammert DILI boundary |
| `mw_max_da` | 500 | **400** | Lammert 2010 MW boundary (DILI) |

i.e. the system recommends filtering the hERG/DILI-liable chemotype on re-run. **The re-run is a deliberate
human step (reactive/advisory), not an autonomous restart.**

> **Honesty flag (carried from the source).** For this already-completed run, the *live SSE was→now payload*
> was not retrievable post-hoc — the suggestion store is per-gunicorn-worker in-memory and is not proxied by
> the public Node API (404). The table above is the **deterministic output of the same `param_tuner` code**
> given the captured gate values; the **gate-fire itself is the durable, live-captured fact** (the run-record
> `qc_gates`). Capturing the live SSE param-diff requires running `frontend/e2e/autoloop-live-proof.e2e.ts`
> within the same request window — noted as an open production step, not claimed as done.

### 3.4 The control — the gate discriminates

An earlier run of the same workflow on a **safe** panel (aspirin/caffeine/ibuprofen), run
`46953d98-fd2a-4df5-9ebe-74786311f899`, completed with **`qc_gates: []`**. The gate stays silent on safe
chemistry and fires only on the real liability. This contrast is the proof the gate is *meaningful* — it
discriminates rather than always-firing.

### 3.5 Why it lands

No surveyed competitor (Biomni, FutureHouse/Kosmos, Seqera AI, Insilico, Recursion, Isomorphic, Genentech,
Owkin, Benchling) demonstrates **chat-driven QC-gate detection + grounded remediation over an executed
drug-development pipeline** (`competitors_ai_agents.md`, Key Questions 2–3). Code-sandbox agents execute
ad-hoc code with no validated-workflow provenance and no scientific QC gate; closed pharma platforms run
real pipelines but only internally for their own programs. BioMate's differentiator is the *combination*:
chat → catalog routing → managed execution → scientific QC auto-loop with cited remediation → auditable
report. **All ADMET values above are Chemprop/ADMET-AI (MPNN) estimates requiring experimental
validation.**

---

## 4. The drug-development workflow suite

BioMate's drug-development capability spans the classical-ML → deep-learning → generative/RL → physics
modeling ladder and the statistical PK → population → trial ladder. The planned tutorial decomposition
(`docs/20261004_DL_ML_MODULE_TUTORIAL_PLAN.md`) organizes these as:

**Models from structure (Design/Make/Test).**
- **QSAR (classical ML):** `Qsar Rf Model`, `herg_cardiac_safety_qsar` — random-forest activity/tox from
  structure; partner-data training + applicability-domain support.
- **ADMET deep learning:** `predict_admet_properties` (ADMET-AI / Chemprop MPNN graph neural network) —
  the model behind the Section 3 hero.
- **Generative lead design:** `REINVENT4 Generative Lead Design`. **Honesty flag:** the committed audit
  (`docs/20260911_GUANGZHOU_AI_DRUG_DESIGN_CAPABILITY_AUDIT.md`) states this workflow *currently implements
  transparent RDKit/BRICS enumeration and filtering — it is not REINVENT reinforcement-learning de-novo
  generation*; a learned generator is available only as a BioNeMo integration point or via the customer
  model registry. Do **not** describe it as production RL-generative without qualification.
- **Docking / virtual screening:** AutoDock Vina, DiffDock, licensed Glide, DrugCLIP; pocket/druggability
  analysis; anti-target/proteome selectivity. A committed docking-triage metric of **78.9%** exists
  (triage/routing accuracy, `leaderboard.md` footnote §) — note this is *triage*, not a Spearman
  ligand-ranking score.
- **Binding free energy (physics):** `openfe_rbfe` (OpenFE RBFE), GROMACS/AMBER MD, MM-GBSA — tiered,
  high-cost refinement for the highest-value series.

**Statistical / translational models.**
- **Non-compartmental PK:** `Nca Pknca`, `Dose Response`.
- **PBPK (mechanistic ODE):** `pbpk_simulation`, `simcyp_pbpk`, pediatric/pregnancy variants.
- **Adaptive dose-escalation (Bayesian):** BOIN.
- **Survival:** `survival_analysis_km`, `rlassocox` (Cox).

**Multi-objective campaign optimization.** A Bayesian optimizer (`bayesian_optimizer.py`) provides
per-objective Gaussian-process surrogates, hypervolume-improvement acquisition, Pareto selection and
diversity-aware next-batch proposals; assay ingestion (`assay_ingestion.py`/`assay_schema.py`), a custom
model registry (Python/Docker/REST adapters), commercial-availability checks and CRO order export close the
Design–Make–Test–Analyse loop (`20260911_GUANGZHOU_AI_DRUG_DESIGN_CAPABILITY_AUDIT.md`).

**Scope figures (committed, with provenance).** The Guangzhou capability audit records **53
drug-discovery workflow modules and 55 pharmacology modules** at the subworkflow-source level (distinct
from the catalog-domain counts of drug_discovery 200 / pharmacology 39, which count catalog rows). **FLAG:**
a "~215 real tested drug-dev workflows" figure appears in internal memory but was not pinned to a single
committed artifact in this pass; cite the 24/24-batch and 53+55-module figures, which are committed.

---

## 5. Benchmarks (honest)

Numbers are reported exactly as committed, with cross-harness vs same-item provenance made explicit.
Source: `evaluation/datasets/public_export/leaderboard.md`, `docs/20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md`,
`docs/20260501_INTENT_CLASSIFICATION_AND_BOIN_100PCT.md`.

| Capability | BioMate | Provenance / caveat | Honest reading |
|---|---|---|---|
| Routing (intent → workflow) | **0.965** (n=200, CI [0.930,0.983]) | BioMate harness | Catalog-driven; frontier LLM given the same catalog reaches the same band |
| param_prefill (context → params, F1) | **0.848** (n=115) | BioMate harness (n differs from the LLM sweep's 170) | vs LLMs-direct 0.62–0.76 |
| protocol-QC | **0.925** (n=20) | BioMate harness | vs LLMs-direct 0.33–0.63 |
| **PBPK within-2-fold (same-item)** | **0.200** (3/15) | Same-item on the exact 15 RealBio compounds (`pbpk_benchmark_sameitem.jsonl`) | **Ties** best LLM (GPT-5.6, 0.200); **beats** LLM mean 0.075; BioMate does **not** lead PBPK — its generic workflow systematically over-predicts Cmax (no first-pass/high-clearance model) |
| BOIN (dose-escalation) | 0.80 (48/60) internal | **Cross-harness**, n=60 internal decisions (2026-04-29 matrix) | **Same-item BOIN is PENDING** (not item-matched to the RealBio exact-MTD task; rerun infra-blocked). For reference, raw-LLM best on the RealBio item-matched BOIN = 0.45 (GPT-5.6) |
| Docking ligand ranking (Spearman) | **not committed** | — | BioMate ranks via Vina/DiffDock but no Spearman score is committed on these items |

> **PBPK — use the honest number.** The same-item PBPK within-2-fold accuracy is **0.200**. A previously
> circulated **100%** figure was **cross-harness** (an 18-case FDA-guidance disease-state Cmax-*ratio* task
> on a different, easier compound set) and is **withdrawn** — it must not be presented as a same-item
> head-to-head. **FLAG:** the leaderboard's own "Headline (honest)" paragraph still prints the stale "pbpk
> 100%" alongside the corrected 0.20 cell — a contradiction to resolve before external use.
>
> **BOIN — state cross-harness.** The 100% BOIN figure in `20260501_...BOIN_100PCT.md` and the 0.80
> leaderboard cell are **internal cross-harness** results, not the RealBio same-item exact-MTD task. The
> same-item BOIN run is pending; do not present 0.80/100% as an item-matched head-to-head.
>
> **PK-NCA — FLAG:** the `Nca Pknca` workflow exists, but **no committed PK-NCA benchmark score was located**
> in this pass. Do not report a PK-NCA accuracy number without a committed artifact.

---

## 6. Differentiation

From the competitive survey (`internal/marketing-research/competitors_ai_agents.md`), the field splits into
(1) reasoning/literature agents (Google AI co-scientist, FutureHouse PaperQA2, Owkin K Navigator, Claude for
Life Sciences, OpenAI for Science) that do not run user pipelines; (2) code-sandbox generalists (Biomni,
Kosmos) that execute ad-hoc Python with no validated-workflow provenance; (3) closed pharma platforms
(Recursion/LOWE, Insilico, Isomorphic, Genentech) that run real pipelines but only internally; and (4)
dev-tooling closest to "generate + run Nextflow" (Seqera AI), positioned as an IDE/CLI pipeline generator,
not a chat-to-managed-run product with a scientific QC auto-loop.

BioMate's defensible lane is the **combination no surveyed product advertises**: (a) reproducible, versioned
pipeline provenance (vs ad-hoc generated code); (b) a **scientific QC auto-loop (gate → cited halt →
grounded remediation) over executed outputs** — the clearest unique mechanism; (c) user-data-in,
managed-compute execution open to any lab's own SMILES/structures; (d) breadth of a validated catalog; and
(e) run-outputs → auditable deliverables. We cannot prove no stealth competitor exists (absence of
evidence), and the competitor facts carry vendor-claim caveats where noted in the source.

---

## 7. Limitations

1. **Predictions are model estimates.** All ADMET values (hERG, DILI, Ames, CYP, permeability, etc.) are
   Chemprop / ADMET-AI (MPNN) estimates and require experimental validation. The hero hERG IC50 of 0.012 µM
   is a model estimate derived via a power-law anchored to terfenadine
   (`herg_ic50_method: admet_ai_prob_powerlaw_terfenadine_anchor`), not a measured patch-clamp value.
2. **Remediation is reactive / advisory, not autonomous.** The auto-loop emits a suggestion + SSE parameter
   diff; the re-run is a deliberate human action. BioMate does not perform a fully autonomous closed-loop
   restart.
3. **No wet-lab validation.** This work makes no claim of experimental or clinical validation of any
   candidate, and no discovery claim.
4. **Benchmark honesty.** BioMate ties (does not lead) on same-item PBPK (0.200) and systematically
   over-predicts Cmax; BOIN and docking-ranking same-item cells are cross-harness or pending; PK-NCA has no
   committed score. The generative workflow is RDKit/BRICS enumeration, not RL de-novo generation, in the
   current implementation.
5. **Capture gaps.** The live SSE was→now remediation payload was reconstructed deterministically for the
   completed hero run (the live store was not retrievable post-hoc); filming the live panel is an open
   production step.
6. **Catalog breadth ≠ validation.** Of 4,209 cataloged workflows, 1,092 carry clean real-execution
   evidence; breadth must never be presented as the validated/tested number.

---

## Data & Code Availability

- **License:** CC-BY-4.0.
- **DOI / repository:** `[DOI/REPO TBD]`.
- **Committed evidence artifacts** (this manuscript's claims trace to these):
  - Hero case study & live proof: `docs/20261004_HERO_A_CASE_STUDY.md`,
    `docs/20261004_AUTOLOOP_LIVE_PROOF.md`, raw S3 outputs
    `docs/autoloop_live_proof_20261004/{qc_metrics.json,toxicity_report.json}` (runs
    `d0ff684b-fd91-4e6f-ba0a-ea136b427700`, `46953d98-fd2a-4df5-9ebe-74786311f899`).
  - QC auto-loop architecture & tests: `docs/20260417_ADMET_AUTOLOOP_ARCHITECTURE.md`,
    `backend/experiments/admet_autoloop/`.
  - Workflow suite & campaign optimization: `docs/20261004_DL_ML_MODULE_TUTORIAL_PLAN.md`,
    `docs/20260911_GUANGZHOU_AI_DRUG_DESIGN_CAPABILITY_AUDIT.md`,
    `docs/20260418_DRUG_DEV_BATCH_WORKFLOWS_24_OF_24_PASSING.md`.
  - Benchmarks: `evaluation/datasets/public_export/leaderboard.md`,
    `docs/20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md`
    (`results/biomate_product/pbpk_benchmark_sameitem.jsonl`),
    `docs/20260501_INTENT_CLASSIFICATION_AND_BOIN_100PCT.md`.
  - Catalog counts: `docs/20261004_CATALOG_COUNT_RECONCILIATION.md`
    (`backend/database/galaxy_ai_tools.db`).
  - Competitive survey: `internal/marketing-research/competitors_ai_agents.md`.

---

## Appendix A — Scientific citations embedded in the QC gates (as recorded in the run artifacts)

- hERG / QT: Sanguinetti & Tristani-Firouzi 2006 *Nature*; FDA E14 guidance; Redfern 2003 *Cardiovasc Res*
  58:32; Aronov 2008 (hERG QSAR).
- DILI: Chen et al. 2016 (DILIrank); Lammert 2010 *Toxicol Sci* (logP>4 AND MW>400 boundary).
- Ames / mutagenicity: Kazius 2005 *J Med Chem* 48:312 (29 structural alerts); Mulliner 2016 *Chem Res
  Toxicol* 29:757.

*(These are the literature anchors the QC gates emit in their messages / evidence-tier strings; citation
metadata appears verbatim in `docs/autoloop_live_proof_20261004/qc_metrics.json`.)*

---

## Appendix B — Reviewer-facing honesty checklist (not for the published version)

- [x] No discovery / wet-lab claim anywhere.
- [x] All ADMET values labeled as Chemprop/ADMET-AI estimates.
- [x] Remediation labeled reactive/advisory, not autonomous.
- [x] PBPK reported as honest same-item 0.200; the 100% figure withdrawn and flagged where still present.
- [x] BOIN labeled cross-harness; same-item pending.
- [x] PK-NCA: no committed score — flagged, not reported.
- [x] Catalog reconciled to 4,209 / 1,092 validated.
- [x] Authors `[AUTHORS TBD]`; DOI/repo `[DOI/REPO TBD]`; license CC-BY-4.0.
