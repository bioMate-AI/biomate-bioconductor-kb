# Batch-clean / stratification workstream: data-credential blocker (audit)

Recorded: 2026-11-09. Workstream #2 (highest-leverage structural fix: make the immune FM representation
beat PCA on responder stratification by removing the ~28× study-identity batch leakage). Mandate was
diagnose → cheap-test → report headroom; if the data isn't on Spark, report the blocker and stop.

## Verdict: DATA-CREDENTIAL BLOCKED — cannot cheap-test headroom

Compute is fine (envpin2 torch 2.14.1+cu130 works). The blocker is data access, not GPU.

### What is required vs. what is reachable

| Needed for the real cheap test | Location | Status |
|---|---|---|
| FM checkpoint (compute embedding z, measure its leakage) | `s3://knowledge-datasets-1759951976/.../fullrun_multitask_v1/fullscope/hybrid_model.pt` | **BLOCKED** |
| Gondal 176-donor cohort (the LCO stratification substrate) | `s3://knowledge-datasets-1759951976/.../oncology_clinical_sc/merged_tissue_cluster_update_filt_other_mal_4.RDS` | **BLOCKED**; local `gondal_pb/` cache is EMPTY |
| GSE169246_TNBC counts (2nd responder cohort) | not on Spark | **MISSING** |
| GSE123813 BCC counts + curated labels | local `fs_eval/work/gse123813/` | present, but **11 patients only** |

The `knowledge-datasets-1759951976` bucket is **not public** (`--no-sign-request` → AccessDenied) and the
Spark AWS key is **expired** (`InvalidAccessKeyId`). (Contrast: the Perturb-seq atlas
`s3://genome-scale-tcell-perturb-seq/` IS public and was downloaded this session — this bucket is not.)

### Why the one local cohort cannot substitute

GSE123813 BCC: 53,030 cells × 23,309 genes, **11 patients (6 responder / 5 non-responder)**, metadata =
patient/treatment/cluster (no response column; labels in `icb_response_labels_curated.json`). Leave-
patient-out responder AUROC on 11 patients has variance so large (one patient flip ≈ 0.03–0.17 AUROC)
that any number is noise, not a headroom measurement. Being a single study it also cannot support the
leave-STUDY-out protocol that defines the task. Running it would fabricate a result; not done.

## What the prior evidence already says (unchanged, from memory `project_immune_llm_code_audit`)

The headroom question — "does a batch-clean representation beat PCA 0.734 LCO while reducing leakage?" —
has prior evidence pointing to NO via the data-side route: conditional-mean centering drove the leakage
probe 0.859→0.000 but the responder contrast did not survive ("the signal WAS the batch"); every
centered/scVI-by-patient variant still lost to PCA because batch≈patient and integrating it regresses
out the between-patient responder signal. A clean re-test still requires the blocked data.

## Unblock steps (precise; all non-GPU)

1. Restore `knowledge-datasets-1759951976` S3 credentials on Spark (current key expired), OR stage
   locally: the checkpoint `hybrid_model.pt`, the Gondal RDS, and GSE169246_TNBC counts.
2. Then the exact reproduction + integration test are already coded and ready:
   `code_20261004/strat_confound_eval.py` + `product_gate_local.py` (PCA(20) LCO/LCTO baseline, embedding
   Δ, shuffle-null) and `scvi_atlas_gse243013.py` / `run_atlas_gse243013_spot.sh` (scVI integration).
   Measure leakage probe AND LCO AUROC; integration must beat PCA 0.734 LCO to count as headroom.

## Bottom line

No headroom number producible now — blocked on expired `knowledge-datasets` credentials (checkpoint +
Gondal cohort) and the missing 2nd cohort. The single local cohort (11 patients) is too underpowered to
substitute. Compute (envpin2) and the eval code are both ready; the gate is purely data access.
