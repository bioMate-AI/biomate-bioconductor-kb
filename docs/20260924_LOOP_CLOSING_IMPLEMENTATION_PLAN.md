# Loop-Closing Implementation Plan (PR breakdown)

**Date:** 2026-09-24
**Scope:** turn the 3-pharma-pains strategy (`docs/20260924_PHARMA_LOOP_PAINS_LEVERAGE_SURVEY.md`) into concrete PRs, grounded in the real `biomate-drywet/backend/lib/galaxy/ai/drug_discovery/` modules.
**Design ref:** `docs/20260417_WETLAB_MODEL_FEEDBACK_LOOP.md` (already specifies auto-retrain / uncertainty sampling / generative coupling as gaps).
**Principle:** upgrade/wire components we own; every PR ships with a **multi-metric, leakage-honest** acceptance test — not a single number.

Legend: effort S(≤2d) / M(≤1wk) / L(>1wk). "own" = code already in the module.

---

## Phase 1 — Wire the Learn phase into the generator  *(highest leverage; hits Pain 1 + 3)*

### PR-1a — REINVENT4 reward ← live assay results
- **Goal:** a completed assay round feeds reward into generation (close the loop).
- **Files:** `generators.py` (add a scoring component), `assay_ingestion.py` (expose latest per-compound scores), `auto_retrain.py` (trigger a scoring refresh on `INGEST_ASSAY`), `denovo_pipeline.py` (use the component).
- **Mechanism:** REINVENT4 plugin/REST scoring interface (own wrapper) → a small service that returns the assay-derived objective for a SMILES; fall back to the predictor when no measurement.
- **Deps:** none new (REINVENT4 own). **Effort:** M. **Blocks:** PR-1c.
- **Accept:** on a held-out campaign, reward-weighted generation shifts the proposed batch toward measured-active regions (report DockQ/affinity + **diversity floor** so it isn't reward-hacking); provenance tag `measured-vs-predicted` preserved.

### PR-1b — MolSkill "chemist-desirability" scoring component
- **Goal:** inject medchem intuition into ranking/generation with zero in-house data.
- **Files:** `custom_model_registry.py` + `custom_model_wrapper.py` (register MolSkill), `generators.py`/`denovo_pipeline.py` (add as a scoring component).
- **Deps:** `molskill` (MIT, pretrained). **Effort:** S. **Blocks:** none.
- **Accept:** MolSkill score returned for arbitrary SMILES; ablation shows it changes ranking on a test set; later fine-tunable on our accept/reject logs (PR-4a feeds it).

### PR-1c — DPO-on-SMILES from actives/inactives + accept/reject
- **Goal:** turn negative outcomes + expert edits into a *generator* update (today DPO only touches IND text).
- **Files:** new `dpo_smiles_trainer.py`; source pairs from `assay_ingestion.py` (active vs inactive) + `feedback_router.py`/`regulatory_pair_recorder.py` (accept/reject); fine-tune the REINVENT4 prior via `generators.py`.
- **Deps:** HuggingFace **TRL `DPOTrainer`** (Apache-2.0). *Reimplement the loop — do not adopt any molecule-DPO repo (all unlicensed/research).* **Effort:** M. **Blocks:** PR-1a (reward wiring reused).
- **Accept:** DPO-tuned prior raises active-region sampling **without** collapsing diversity (report all 7 metrics vs the base prior); pairs are org-scoped + PII-stripped (reuse `feedback_io.py` policy).

---

## Phase 2 — Negatives as a first-class signal  *(Pain 3)*

### PR-2a — DrugCLIP consumes *measured* inactives as hard negatives
- **Goal:** convert thrown-away "did-not-bind" data into training signal (today DrugCLIP uses only in-batch/decoy negatives).
- **Files:** DrugCLIP wrapper in `generators.py`/`custom_model_wrapper.py`; `assay_ingestion.py` (surface confirmed inactives).
- **Mechanism:** HCL / iMolCLR reweighting — rank negatives by similarity, oversample hardest measured non-binders.
- **Deps:** none new (DrugCLIP own). **Effort:** M. **Accept:** retrieval AUC on a **leakage-filtered** split improves with measured hard negatives vs decoy-only baseline; no physchem-shortcut inflation (check on CleanSplit-style split).

### PR-2b — Failure-reason taxonomy → Learn
- **Goal:** capture *why* a compound failed (synthesis / potency / hERG / solubility / off-target) instead of collapsing to "low score."
- **Files:** `assay_schema.py` (add `failure_reason` enum + qualifier), `wetlab_report_ingester.py`/`study_report_ingester.py` (parse), `auto_retrain.py` (route reasons to the right objective).
- **Effort:** S. **Accept:** failures carry a typed reason end-to-end; per-reason counts queryable; a tox failure penalizes the tox objective specifically, not the global score.

### PR-2c — DeepCoy hard-decoy padding for sparse targets
- **Files:** new `hard_negative_augment.py` used by PR-2a. **Deps:** DeepCoy (BSD). **Effort:** S. **Accept:** sparse-target retrieval improves; flagged as *synthetic* (never mixed with measured, per the DUD-E-bias caveat).

---

## Phase 3 — Warm-start new targets  *(Pain 2)*

### PR-3a — Chemprop multitask pretrain → transfer fine-tune
- **Goal:** a new target inherits from analogous prior programs.
- **Files:** new `chemprop_transfer.py` registered via `custom_model_registry.py`; eval in `model_validation.py`.
- **Deps:** `chemprop` (MIT). **Effort:** M. **Accept:** on a **family-disjoint** split, transfer beats from-scratch at ≤50 points; **must also beat the physics (Vina) baseline** or it isn't justified.

### PR-3b — Upgrade BayesianOptimizer → transfer-BO (kill the n_initial=16 wall)
- **Goal:** warm-start the surrogate from related assays so a new target doesn't need 16 measurements first.
- **Files:** `bayesian_optimizer.py` (swap sklearn-GP → **BayBE** or **BoTorch multi-task GP + RGPE**), `auto_retrain.py` (feed related-campaign priors).
- **Deps:** **BayBE** (Apache-2.0, chemistry-native) *or* BoTorch/Ax (MIT). **Effort:** M/L. **Accept:** with a warm-start prior, useful proposals at n<16; multi-objective batch via qNEHVI; **keep a from-scratch GP in the ensemble as a negative-transfer floor** (RGPE rank-weighting).

### PR-3c — Leakage-honest eval harness + DrugCLIP triage entrypoint
- **Files:** new `eval_cleansplit.py` (GEMS CleanSplit discipline), DrugCLIP pocket→library triage in `denovo_pipeline.py`.
- **Effort:** M. **Accept:** all Pain-2 claims reported on family-disjoint, leakage-filtered splits; triage returns a ranked shortlist for a novel pocket with a structure.

---

## Phase 4 — Expert UI + SAR guardrails  *(Pain 1)*

### PR-4a — Metis chemist-feedback loop → SAR signal
- **Files:** Metis adapter for REINVENT4 (own); route captured global+substructure feedback into `regulatory_pair_recorder.py`-style store → feeds PR-1c DPO and PR-1b MolSkill fine-tune.
- **Deps:** Metis (MIT). **Effort:** M (includes the REINVENT4-compat adapter Metis lacks). **Accept:** a chemist marks liabilities → those substructures are down-weighted in the next batch.

### PR-4b — SAR/alerts as guardrail scoring components
- **Files:** `generators.py` scoring components wrapping **mmpdb** (transforms) + **RDKit FilterCatalog**/**rd_filters** (PAINS/BRENK/ChEMBL); optionally derive in-house alerts via `bioalerts`.
- **Deps:** mmpdb (BSD), rd_filters (MIT). **Effort:** S. **Accept:** flagged moieties are penalized; MMP transforms surfaced as design suggestions.

---

## Cross-cutting

- **The moat gate (unavoidable):** none of this is validated until a **prospective wet-lab round** shows predicted→measured lift on a real target. Everything above is retrospective/architectural until then — say so in any external claim.
- **Eval discipline (every PR):** report the **full metric vector** (not one number), on **leakage-filtered/family-disjoint** splits, always against a **physics (Vina/FEP) baseline** and a **simple baseline** (train-mean / similarity) — complex methods must beat both.
- **Licenses:** all adopted deps are Apache-2.0/MIT/BSD; commercial rule systems (Derek/StarDrop) are buy-not-build, excluded here.
- **Sequencing:** Phase 1 first (owns the loop + highest leverage), then 2 (negatives), 3 (new targets), 4 (expert UI). Phases 2–4 are largely parallelizable once Phase 1's reward/pair plumbing exists.
