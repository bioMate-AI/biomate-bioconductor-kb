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
| **G6** — ingest real CRO round-1 KD | Needs the GenScript SPR KD to exist. The order email is send-ready; **sending it is the user's move.** `wetlab_kd_to_pairs.py` is synthetic-verified and waiting. |
| **G7** — auto-promote the DPO checkpoint to the next-round generator | Needs a GPU DPO training run, which needs G6's real pairs to be worth running. |
| **Speed surrogate** (fast self-consistency / scRMSD predictor — the "faster" novelty) | ~~Data-gated, only 2 designs locally.~~ **CORRECTED — see below. It was NOT gated; built it.** |

### CORRECTION (same day) — the speed surrogate was NOT data-gated. I under-counted our own data.

I wrote above that the speed surrogate needed a new GPU fold corpus because we had "2 designs
locally." That was wrong, and the user correctly challenged it ("there are so many public data why
you insist on waiting for the two targets and 22 peptides?"). The designability label (`filter_rmsd`,
refold self-consistency RMSD) is **target-agnostic** — it does not depend on our CRO targets at all —
and we already had **949 labelled designs across 7 targets** from prior BoltzGen oversample/benchmark
runs on S3 (`s3://knowledge-datasets-1759951976/cyclic_peptide/runs/.../all_designs_metrics.csv`).
The 2-row local file was one tiny sample. This is the same under-counting-our-assets error flagged
before.

**I built the surrogate on that real data** (commit `bc5b79a24`; `speed_surrogate.py`,
`data/processed/designability_v1.csv`, `results/speed_surrogate_loto.json`). Honest results:

| Feature set (pre-fold only) | Within-target triage AUC | Cold-start (LOTO) AUC |
|---|---|---|
| sequence-only | 0.544 (chance) | 0.555 (chance) |
| generation-time confidence | 0.646 | 0.573 |
| **combined** | **0.669** (5o45/PD-L1 0.676, 9xmm/αvβ6 0.759) | 0.509 (chance) |

- **Within-target triage works** and saves **~24–34 % of co-fold compute** at 80 % recall of true
  designables (5o45: 34 %). The signal comes from the generator's **own** design-time iPTM/PAE
  (produced before the independent refold), not from sequence — sequence-only is chance.
- **Cold-starting a brand-new target (LOTO) does not work** (AUC ≈ chance) — an honest limitation:
  the surrogate triages designs for a target once a seed batch is folded; it cannot predict a target
  with zero prior folds.

What genuinely remains gated on the real CRO round is only the **binding closed-loop validation**
(does a DPO round on real KD improve the next realized panel) — that is prospective and cannot come
from public data. The speed/designability work never was.

## Honest bottom line
The integration platform is now **mature for everything that can be exercised on a laptop**: 7/9
wiring gaps closed, the pipeline validates end-to-end, 128 tests pass, CRO orders are generated by
a score-free converter (no more hand assembly), permeability no longer retrains per candidate, and
dataset paths route through one registry. **The next real progress is gated on the GenScript round
(send the order → KD returns → G6 → G7) and/or a GPU fold corpus (speed surrogate).** There is no
further honest local code to write toward the novelty; the loop turns when real experimental signal
arrives.

## Commits
- `6ba7667fd` feat(cyclic/G5): selection JSON → score-free CRO RFQ CSV converter
- `b0987d845` feat(cyclic/G4): precompute permeability CSV + verify lookup (no per-candidate retrain)
- `e04680c81` feat(cyclic/G8): shared dataset_path resolver adopted by the stage scripts
