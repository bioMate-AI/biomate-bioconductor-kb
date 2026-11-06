# Cyclic-Peptide Integration — Local Wiring Gaps Closed (G4, G5, G8) + Honest Gating

**Date:** 2026-10-04 · **Scope:** finish the locally-buildable integration maturation for the
cyclic-peptide DBTL pipeline, then honestly mark what remains gated on the real world.
**Working dir:** `research/guangzhou_all_atom/`. **Prior state:** 4/9 wiring gaps closed
(G1 normaliser, G2 fold→pool, G3 honest binding advisory, G9 pocket dedup); G8 partial.

## What changed this session

Pipeline validator went **4 closed → 7 closed** (`cyclic_pipeline.py --validate`:
"11 stages, 2 OPEN wiring gaps (7 closed), all scripts present, all datasets resolve, DAG acyclic").
Full test suite **128 passed** (was 124 + 4 new).

### G5 — selection JSON → score-free CRO RFQ CSV  (commit `6ba7667fd`)
`select_to_rfq.py`. Until now the `results/*_CRO_order.csv` / `CRO_SEND_*.csv` panels were
assembled **by hand**. The converter:
- accepts all three selection shapes — `peptide_select` `SelectionResult.to_dict` (`selected` ids),
  `mo_select_qnehvi` pool JSON (`pools.<target>.<rank>_topk`), and a plain id/dict list;
- resolves id → sequence/smiles/cyclization from the candidate pool;
- emits the exact GenScript `CRO_SEND` schema.
- **SCORE-FREE BY CONSTRUCTION:** fixed output columns + an `_assert_score_free` guard that fails
  loud if any internal design score (ΔG / iPTM / pAff / HVI / RUSH) would reach a CRO row. This
  enforces the "never leak internal scores to the CRO" rule in code, not just by convention.
- Tests: `test_select_to_rfq.py` (7). Verified it regenerates the PD-L1 composite top-10 from the
  committed `mo_qnehvi_rescore.json` with no score columns. (The historical hand-made panel differs
  because it came from the earlier MM-GBSA-screened selection, not this rescore JSON — the converter
  faithfully reproduces whatever selection it is handed; that is the point.)

### G4 — precompute permeability CSV + verify lookup  (commit `b0987d845`)
`predict_permeability_pool.py` + `peptide_verify.perm_pred_csv`. **Root-cause fix, not a patch:**
the old `_score_permeability` **re-trained the full CycPeptMPDB bootstrap-bagged ensemble from
scratch for every candidate** (`perm.load` + `bagged_fit_predict` inside the per-candidate call) —
O(N) full retrains per pool.
- `predict_permeability_pool.py` trains the ensemble **once** and predicts the whole pool in a
  single batched call → per-candidate CSV (`identifier,sequence,smiles,logPapp_mean,logPapp_std`).
- `peptide_verify` (`_score_permeability` + `verify_peptide`/`verify_batch`) and `peptide_loop`
  (`LoopConfig.perm_pred_csv`) now **look up** the value (id→smiles→seq) instead of retraining;
  they fall back to live training when a row is missing, so the numbers are identical either way.
- Tests: `test_perm_pool_g4.py` (7) — lookup keying, provenance, NaN-std→None, graceful fallback,
  verify threading, pool normalisers.

### G8 — shared dataset-path resolver adopted by the stage scripts  (commit `e04680c81`)
`dataset_path.py` — one resolver (cache-first via `cyclic_data_registry`, committed relative path
as fallback). Behaviour-preserving (the registry local_path for these datasets equals the committed
path). Adopted by the dataset-consuming **stage** scripts: `peptide_verify.py`,
`predict_permeability_pool.py`, `permeability_predictor.py`, `stability_predictor.py`,
`train_binding_model.py` (now defaults `--csv` to `binding_affinity_v1`), `mo_select_qnehvi.py`.
- **Documented exceptions (intentionally not migrated, honest):** `rebuild_stability_folds.py`
  targets a file *nested inside* the `peptideclm2_pepmsnd` tree (the registry resolves the tree
  root, not that CSV); `collect_*` / `cycpeptmpdb_to_pepglad.py` **produce** datasets rather than
  consume registry paths.
- Tests: `test_dataset_path.py` (4).

## What remains — honestly, all GATED on the real world (not more local code)

| Gap / item | Why it is not buildable locally now |
|---|---|
| **G6** — ingest real CRO round-1 KD | Needs real measured KD to exist. `wetlab_kd_to_pairs.py` is synthetic-verified and ready for when experimental signal arrives. |
| **G7** — auto-promote the DPO checkpoint to the next-round generator | Needs a GPU DPO training run, which needs G6's real pairs to be worth running. |
| **Speed surrogate** (fast self-consistency / scRMSD predictor — the "faster" novelty) | ~~Data-gated, only 2 designs locally.~~ **CORRECTED — it was NOT gated; built it on 949 existing designs. Full write-up: [`20261004_SPEED_SURROGATE_DESIGNABILITY.md`](20261004_SPEED_SURROGATE_DESIGNABILITY.md).** |

> **Correction (same day):** the "data-gated" claim above was wrong — I under-counted our own data.
> The designability label is target-agnostic and we already had 949 labelled designs (7 targets) on
> S3. The surrogate was built and evaluated (within-target triage saves ~24–34 % of co-fold compute;
> sequence-only and cold-start are chance). Details, dataset, and honest limits are in the dedicated
> doc linked in the table.

## Honest bottom line
The integration platform is now **mature for everything that can be exercised on a laptop**: 7/9
wiring gaps closed, the pipeline validates end-to-end, 128 tests pass, CRO orders are generated by
a score-free converter (no more hand assembly), permeability no longer retrains per candidate, and
dataset paths route through one registry. The **speed/designability surrogate was built on 949
existing designs** (NOT gated — see the correction above): within-target triage saves ~24–34 % of
co-fold compute, cold-start does not work. The only remaining open item is the binding closed-loop
*validation* (G6 → G7: does a DPO round on real measured KD improve the next realized panel) — that
is prospective and needs real experimental signal; no public data substitutes for it. All model,
selection, permeability, and speed/designability work trains and evaluates on data already in hand.

## Commits
- `6ba7667fd` feat(cyclic/G5): selection JSON → score-free CRO RFQ CSV converter
- `b0987d845` feat(cyclic/G4): precompute permeability CSV + verify lookup (no per-candidate retrain)
- `e04680c81` feat(cyclic/G8): shared dataset_path resolver adopted by the stage scripts
- `9e439592c` docs: integration gaps closed (G4/G5/G8) + gating (this doc, initial)
- `bc5b79a24` feat(cyclic): designability speed surrogate on 949 existing designs
- `5aea56b7a` docs: correct speed-surrogate 'data-gated' claim; record real result
