# Cyclic-Peptide Integration Foundation — Unified Data Registry + Pipeline Orchestration

**Date:** 2026-10-04 · **Priority #1** (mature integration foundation) · Local build + verify only, no GPU/EC2.

This is the orchestration + maturity layer the integration map
(`docs/20261004_CYCLIC_PEPTIDE_INTEGRATION_MAP.md`) called for: one addressable data registry over
our scattered S3 datasets, and one declarative stage manifest over our scattered stage scripts.
Everything here was built and verified locally.

**Artifacts (in `research/guangzhou_all_atom/`):**

| File | Purpose |
|---|---|
| `cyclic_data_registry.yaml` | Manifest cataloguing every held dataset (name, S3 path, schema, verified count, modality) |
| `cyclic_data_registry.py` | Loader: `load(name)`, `catalog()`, `verify()`, `fetch()` — local-cache-first, S3 on demand |
| `cyclic_pipeline_manifest.yaml` | Declarative 11-stage DBTL manifest: stage → scripts + I/O contract + datasets + maturity + wiring gaps |
| `cyclic_pipeline.py` | Parser/validator/reporter: checks scripts exist, datasets resolve, DAG acyclic; prints stage map + gaps |

---

## 1. Unified Data Registry (datasets + counts + modalities)

Every count below is a **real, verified count** (header/line/index-length read on 2026-10-04), not an
estimate. `verify()` re-reads the 11 accessible datasets and matches all 11 to the manifest
(0 mismatches); the 4 multi-GB archives are correctly skipped as not-directly-loadable.

| Dataset | Modality | Format | Records | Cyclic | Unit |
|---|---|---|---:|---:|---|
| `cycpeptmpdb` | permeability | csv | 8,466 | — | peptides (PAMPA/Caco2/MDCK/RRCK) |
| `binding_affinity_v1` | binding | csv | 136,730 | 36,102 | measurements (ChEMBL+BindingDB; 2,702 UniProt targets) |
| `bindingdb_peptide` | binding | csv | 171,006 | — | rows (BindingDB subset feed) |
| `approved_cyclic_peptide_drugs` | reference | csv | 54 | — | approved drugs |
| `cremp_partial` | conformer | csv | 36,198 | — | conformer ensembles (+29 GB pickle / 14 GB sdf archives) |
| `macroconf` | conformer | archive | — | — | macrocycle NMR systems |
| `pepbdb` | structure | json | 13,481 | 890 | peptide entries (446 cyclic clusters) |
| `pepbench` | structure | archive | 6,105 | — | complexes (4,157 train / 114 val; +93 LNR test; +70,498 ProtFrag) |
| `rcsb_cyclic_index` | structure | json | 28,662 | — | candidate PDB entry IDs (not structurally verified) |
| `bound_cyclic_agg` | structure | jsonl | 776 | 776 | bound cyclic complexes (deduplicated) |
| `bound_cyclic_v1` | structure | jsonl | 236 | 236 | bound cyclic complexes (first pass) |
| `nme_v1` | sequence | jsonl | 1,225 | — | N-methylation records (1,104/46/75 train/val/test) |
| `helm_monomers` | reference | archive | — | — | HELM non-canonical monomer library |
| `peptideclm2_pepmsnd` | sequence | archive | — | — | peptide sequences + stability source |
| `pepmsnd_stability_folds` | sequence | csv | 605 | — | fold-assigned peptides (derived, leak-controlled) |

**15 datasets; summed record_count = 403,405.** Modalities present: binding, permeability, conformer,
structure, sequence, reference — the full set the integration map claims we hold jointly.

**Two manifest counts the registry caught + corrected** (the registry doing its job):
`bindingdb_peptide` is 171,006 rows in the held CSV (the harmonization summary's "170,868" is BindingDB
raw rows pre-dedup, a different quantity); `bound_cyclic_v1` holds 236 unique PDB IDs in the manifest.jsonl
(summary.json reports 235). Both corrected to the true held-file counts.

**Loader interface:** `registry().load("cycpeptmpdb")` → DataFrame; `load("pepbdb")` → dict;
`load("bound_cyclic_agg")` → list[dict]; archives raise with the S3 URI + `fetch()` guidance. Canonical
store is S3 (`s3://knowledge-datasets-1759951976/cyclic_peptide/...`); `local_path` is an optional cache
(gitignored under `data/`), so the committed artifacts are the `.py` + `.yaml` only.

---

## 2. Pipeline orchestration — stage → script map

Declarative 11-stage DBTL manifest. Topological order (ignoring the intended `dpo_learn → generate`
close-back): `target_prep → generate → fold_selfconsistency → score_binding → score_permeability →
score_developability → gate_and_verify → multi_objective_select → synth_rfq → assay_ingest → dpo_learn`.

| Stage | Scripts (existing) | Runs on | Maturity |
|---|---|---|---|
| **target_prep** | `avb6_pocket_truncate.py`, `pdl1_m2c_stage_target.py`, `boltzgen_ourtarget.sh` | local | partial |
| **generate** | `launch_rfpeptides.sh`, `launch_unimomo_cyclic_ft.sh`, `launch_boltzgen_oversample.sh`, `pdl1_m2c_generate.py`, `developability_guidance.py` | gpu | untested_local |
| **fold_selfconsistency** | `refold_rerank_driver.sh`, `launch_refold_rerank.sh`, `build_candidates.py`, `selfconsistency_rerank.py`, `scrmsd.py`, `cyclize_and_rescore.py` | gpu | partial |
| **score_binding** | `train_binding_model.py`, `binding_features.py`, `launch_mmgbsa_pool.sh`, `peptide_mmgbsa_pocket_run.sh` | ec2_batch | tested_local |
| **score_permeability** | `permeability_predictor.py`, `build_physchem_calibration.py`, `perm_uncertainty.py`, `perm_size_correction.py` | local | tested_local |
| **score_developability** | `developability_guidance.py`, `stability_predictor.py`, `rebuild_stability_folds.py`, `noncanonical_vocab.py` | local | partial |
| **gate_and_verify** | `peptide_gate.py`, `peptide_verify.py`, `peptide_loop.py` | local | tested_local |
| **multi_objective_select** | `mo_select_qnehvi.py`, `peptide_select.py`, `multi_property_selection.py`, `property_guided_selection.py` | local | tested_local |
| **synth_rfq** | *(none — manual CRO order CSV)* | external_cro | untested_local |
| **assay_ingest** | `campaign_assay_to_pairs.py`, `wetlab_kd_to_pairs.py` | external_cro | partial |
| **dpo_learn** | `dpo_pairs.py`, `dpo_peptide_trainer.py`, `dpo_unimomo_adapter.py`, `simulate_closed_loop.py` | gpu | partial |

The in-memory orchestrator `peptide_loop.py` already chains `gate_and_verify → select → dpo_learn(emit)`
with pluggable stage interfaces; the full-pipeline wiring gaps below are what remain to make it hands-off.

### I/O contract (summary)

Each stage declares `inputs` / `outputs` in the manifest. The load-bearing chain:
`target_prep` → pocket complex → `generate` → poses+sequences → `fold_selfconsistency` →
`candidates.jsonl (id, dockq, likelihood, scrmsd, confidence)` → the three scorers →
`gate_and_verify` (ingests physics_json ΔG + permeability CSV + stability CSV) → verified property
vector → `multi_objective_select` → selected batch JSON → `synth_rfq` → CRO order → `assay_ingest` →
preference pairs → `dpo_learn` → fine-tuned checkpoint → back to `generate`.

---

## 3. Top wiring gaps to close for a mature pipeline

9 concrete gaps, in priority order (severity in the manifest):

1. **G3 (high) — learned binding model not wired into verify.** `train_binding_model.py` produces
   `binding_model_prod.pkl`, but `peptide_verify._score_affinity` ingests ΔG **only** from `physics_json`
   (MM-GBSA). The learned model is not an affinity source — the integration map's "wire as the binding
   scorer" is unmet. *Highest-leverage single fix: add the learned model as an affinity channel in verify.*
2. **G2 (high) — fold output → scoring loop.** `selfconsistency_rerank.py` emits per-target
   `candidates.jsonl`, but nothing converts it into `peptide_loop`'s pool (`{identifier,seq,smiles}`) or
   into verify input. Needs one adapter.
3. **G1 (high) — generator output → fold input.** RFpeptides / UniMoMo / BoltzGen / PepGLAD-M2c each
   emit different layouts; no normaliser feeds `build_candidates.py`. Each generator is wired by hand.
4. **G7 (high) — learn → generate close-back is a stub.** `peptide_loop`'s `LearnHook` records pairs but
   does not train; `dpo_peptide_trainer.py` produces a checkpoint that is **not** auto-promoted to the
   next round's Generator. The loop does not yet compound.
5. **G6 (high) — no real CRO KD ingested.** `wetlab_kd_to_pairs.py` / `campaign_assay_to_pairs.py` are
   synthetic-verified only; the closed loop has never run on real experimental signal (pending round-1).
6. **G4 (medium) — permeability predictor → loop.** `permeability_predictor.py` emits a log-Papp CSV, but
   the loop defaults to a raw CycPeptMPDB lookup; no step produces the predictor CSV and points
   `perm_csv` at it.
7. **G5 (medium) — select → synth RFQ.** No script converts a selection JSON into a GenScript RFQ / CRO
   order CSV; `results/*_CRO_order.csv` were built by hand.
8. **G8 (medium) — registry adoption.** Stage scripts hard-code dataset paths; none import
   `cyclic_data_registry` yet. This PR ships the registry; migrating the scripts is the follow-up.
9. **G9 (low) — target_prep not one module.** Pocket extraction is duplicated across
   `avb6_pocket_truncate.py`, `pdl1_m2c_stage_target.py`, `boltzgen_ourtarget.sh`.

---

## 4. Maturity checklist (tested vs not)

| Stage | Local test / artifact evidence | Status |
|---|---|---|
| target_prep | avb6/pdl1 pockets produced; no unit test | partial |
| generate | GPU/EC2-only launchers | ☐ untested_local |
| fold_selfconsistency | `scrmsd.py --selftest`, `selfconsistency_rerank.py --selftest` run; full refold GPU | partial |
| score_binding | `train_binding_model.py` ran → `binding_model_prod.pkl` + metrics JSON; MM-GBSA is EC2/GPU | ✅ tested_local |
| score_permeability | `permeability_predictor.py` runs on CycPeptMPDB + results | ✅ tested_local |
| score_developability | `test_rebuild_stability_folds.py` passes; `developability_guidance.py` no local run | partial |
| gate_and_verify | `test_peptide_verify.py`, `test_peptide_loop.py` pass | ✅ tested_local |
| multi_objective_select | `test_peptide_select.py` passes; `mo_select_qnehvi.py` produced panels | ✅ tested_local |
| synth_rfq | no script; manual | ☐ untested_local |
| assay_ingest | `test_wetlab_kd_to_pairs.py` passes (synthetic only) | partial |
| dpo_learn | `test_closed_loop_integration.py` runs `simulate_closed_loop.py`; trainer GPU | partial |

**Rollup: tested_local = 4, partial = 5, untested_local = 2.** The local scoring/selection/verify spine
(score_binding model, permeability, gate+verify, MO-select) is tested; the GPU generation+fold ends and
the external CRO loop are the untested/partial segments, exactly where the high-severity wiring gaps sit.

---

## 5. Local verification performed

- `python3 -m py_compile cyclic_data_registry.py cyclic_pipeline.py` — clean.
- `python3 -c "import yaml; yaml.safe_load(...)"` on both manifests — parse clean.
- `cyclic_data_registry.py --verify` — 11 accessible datasets re-read, **0 count mismatches**, 4 archives
  skipped; 2 manifest counts corrected against real held files during the build.
- `cyclic_pipeline.py --validate` — **OK**: 11 stages, 9 wiring gaps, all referenced scripts present on
  disk, all dataset refs resolve against the registry, DAG acyclic.

## 6. Next steps (to mature, not in this local-only PR)

Close G3 first (learned binding model into verify — pure local wiring, highest leverage), then G2/G4
(fold + permeability adapters into the loop — local), then G1/G7 (generator normaliser + checkpoint
promotion — needs a GPU round to exercise), and finally G6 (real CRO round-1 KD → turn the loop on).
Migrate stage scripts to resolve datasets through the registry (G8) opportunistically as each is touched.
