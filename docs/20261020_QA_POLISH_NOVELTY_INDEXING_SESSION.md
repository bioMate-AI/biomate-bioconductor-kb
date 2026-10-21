# 2026-10-20 — QA polish + drug-dev deck audit + novelty/FTO indexing

Autonomous QA/polish + demo-capture session. This doc records what landed, what
was audited, and the open items. All code fixes below are committed on branch
`cursor/tutorial-live-recording-and-report-editing-4ea7`.

## Shipped (committed)

| Area | Fix | Commit |
|---|---|---|
| ADMET step attribution | `predict_admet_properties` publishes outputs to a step-named dir (`02_predict_admet_properties`) instead of a phantom `run` step, so after-run Outputs attribute to the real step "Predict Admet Properties". | `ba7389a59` |
| ADMET verify/audit | E2E captures for step display + after-run step attribution (`admet-step-verify.e2e.ts`, `admet-stepdetail-audit.e2e.ts`). | `40d025df8`, `20db72fe4` |
| Stuck-"running" runs | Finalize runs orphaned by a backend restart (`interrupted → failed`) + background reaper that reconciles stale non-terminal runs for dashboard freshness. | `80ec82f0a`, `e09dd2e18` |
| Progress stream | Compact auto-scrolling progress box (Claude-style), no WF/QC pills, no fold caret. | `2b41d859c` |
| Deck captures | Drug-dev deck series prerun-only captures (dd1–dd17, no Batch spend) + `DECK_ONLY` filter + robust send-click. | `90f5a6c8a`, `540115bc6` |

(CN1C phantom-param fix, composer instruction button, shared file/output
visualization, and after-run download-arrow + larger preview landed earlier in
the session; see prior commits.)

## Novelty / FTO workflow — indexed + chainable (DB; deployed via sync, not git)

**Problem.** dd4 ("Score chemical novelty and freedom-to-operate for these hits:
…") mis-routed to **Pharmacophore Filtering**, because `compound_novelty_scorer`
existed on disk (`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/compound_novelty_scorer/main.nf`)
but was **not indexed** in `galaxy_ai_tools.db`.

**Fix.** Ran the indexer's incremental Phase 4 (`index_biomni_nextflow`) only —
avoids the tools phases where an earlier full run hit a transient
"database disk image is malformed". This added 12 genuinely-new biomni_nextflow
subworkflows (all real `.nf` on disk, previously unindexed):

- drug_discovery: **Compound Novelty Scorer** (id 14654), MPO Denovo Optimization,
  Reinvent4 Finetune RL, Amber Peptide MMGBSA, Peptide MMGBSA
- structural_biology: Cyclic Peptide Cofold
- proteomics: Phospho Localization
- genomics: ACMG Variant Interpretation
- lab_automation: Nanodrop Purity QC, RIN Bioanalyzer QC, Cell Counter Viability QC
- transcriptomics: ONT RNA-seq

Catalog `4211 → 4223`, `PRAGMA integrity_check = ok`. Set
`Compound Novelty Scorer.output_types = ["json"]` (the `.nf` emits
`*_novelty.json`) so it chains both directions (input `query_smiles` ← generative/
screening upstream; output `json` → downstream).

**Routing verified** against the real router's FTS component (dense `.npz` not
present locally): for "novelty/freedom/patent/tanimoto/scaffold", bm25 ranks
`Compound Novelty Scorer` #1 at **-32.2** vs next (-16.9); Pharmacophore Filtering
does **not** match novelty terms at all. dd4 will route correctly after the DB
sync lands on dev.

**Deploy:** `scripts/sync_to_dev.sh` (db layer). DB is gitignored (328 MB → dev +
S3), so this change is not in git — it ships through the sync.

## Audited deck panels (prerun)

- **dd1 target-id** — ❌ workflow title renders **"Untitled"** (`workflowDefinition.name`
  empty for the target-id card). Params correct (Disease, Criteria). Root-cause
  trace in progress; fix = give the target-id card a display name.
- **dd4 novelty/FTO** — ✅ fixed by indexing (was Pharmacophore Filtering).
- **dd15 cyclic peptide** — ✅ routes to `cyclic_peptide_design`, Target parsed
  (integrin αvβ6). Minor: name is snake_case, not Title Case.
- **dd16 clinical trial** — ✅ Clinical Trial Simulation, 20 params, BOIN input
  resolved.

## ADMET step-attribution fix — verified (deterministic + empirical)

The live E2E (`admet-step-verify.e2e.ts`, fresh Batch run) exceeded its 45-min
window waiting on the UI "COMPLETED" badge — Batch runtime, not the fix — so it
captured no screenshot. Rather than relaunch a ~$1.50/45-min speculative run
(forbidden by the "No Speculative Deploys" rule), verified two cheaper ways:

1. **Deterministic (code trace).** publishDir writes to
   `{outdir}/02_predict_admet_properties/`; the step parser does
   `step_id = int(step_dir.split("_")[0]) - 1` → `int("02")-1 = 1`, and indexes
   the process under the unprefixed `predict_admet_properties` — both resolve to
   step 1 "Predict Admet Properties" in the viewer's `nfProcessByName` lookup.
   (Old `run/` → `int("run")` raised → fell back to a phantom "run" step.)

2. **Empirical (actual S3 outputs).** The post-fix run invocation
   `fd5a73ac-87df-4850-b8ff-6d768c1b47fb/5cfbb943/` (written 2026-10-20 23:41)
   placed all six real outputs —
   `predict_admet_properties_results.json`, `toxicity_report.json`,
   `pk_summary.json`, `qc_metrics.json`, `predict_admet_properties_output.txt`,
   `versions.yml` — under `…/02_predict_admet_properties/`, NOT `…/run/`. The
   viewer derives the step label from exactly this path, so the Outputs now
   attribute to "Predict Admet Properties". (Pre-fix runs still show 796 files
   under `/run/`; the fix only affects runs after deploy.)

## Open items

1. **dd1 "Untitled"** — apply the display-name fix once the trace lands.
2. **DB sync** — push the novelty indexing to dev (db layer) and re-capture dd4.
3. **Dense embeddings** — the 12 new workflows have no `.npz` embedding yet; FTS
   covers exact-term routing (dd4 verified), but a dev-side embedding backfill
   would restore semantic recall for them.
4. **Demo videos** — generate from captures and push to **Google Drive**.
