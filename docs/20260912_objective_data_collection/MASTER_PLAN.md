# Master plan — objectives, data, and model-design reconciliation

Date 2026-09-13. Plans ALL items and executes them in parallel. Preserves the
canonical distinction from `biomate-immune-llm/.../OBJECTIVES.md`: the FM trains only
H1–H4 (mechanism, central dogma → presentation); "correct target / druggable / durable
/ irAE / tolerance / efficacy" are produced by a **combiner**, **gates**, and **derived
scores**, NOT by clinical-outcome heads (explicit non-goal). Each workstream is tagged
by role so we never mislabel a validation set as FM training data.

Roles: [FM-TRAIN] trains an H1–H4 head · [VALIDATE] external validation of a derived
score · [COMBINER] target-selection evidence channel · [GATE] druggability filter ·
[FEASIBILITY] inventory that decides spend before building.

Discipline (all workstreams): read S3 with `dangerouslyDisableSandbox:true`; everything
stays `training_eligible=false`; held-out units frozen; ImmPort quarantined pending
leakage sign-off; honest caveats + null baselines; distinct output file per workstream.

## Workstreams (parallel)

| W | Goal | Role | Key inputs (already located) | Output file |
|---|------|------|------------------------------|-------------|
| **W1** | Paired-N audit across ALL objectives — true trainable/validatable N (matched feature+label) per objective, the real "do we have enough" metric | FEASIBILITY | S3 corpus: immport tables_parquet, GEO acquisitions, ribo/proteome/immunopeptidome manifests | `W1_PAIRED_N_AUDIT.{json,md}` |
| **W2** | Vaccine-response validation dataset — pull the 2,125 baseline transcriptomes (`raw/vaccine_paired_baseline_accessions.csv`), assemble expression→seroconversion, study-held-out | VALIDATE | GEO GSMs/SRA from bridge; `immport_vaccine_response.csv` | `W2_vaccine_expr_response.*` |
| **W3** | Safety paired-N + molecular-linked AE dataset — resolve GEO/SRA bridge for the 297 AE arms; true predictable-safety N | VALIDATE | `immport_safety_arm_rates.csv`, expsample_public_repository | `W3_safety_paired.*` |
| **W4** | Therapy-duration expansion — iWITH + the other ~18 withdrawal/tolerance studies → survival tables | VALIDATE | immport/studies/SDY* withdrawal set; iWITH template built | `W4_duration_survival.*` |
| **W5** | Druggability gate — BindingDB (S3 494MB) + ChEMBL → small-molecule ligandability + cyclic-peptide/PPI-interface fit | GATE | `biomni_data_lake/BindingDB_All_202409.tsv.gz`; `druggability_chembl.json` | `W5_druggability_gate.*` |
| **W6** | Target-selection combiner inventory + build spec — availability of genetics/perturbation/pathway/network/proteomic channels; null-calibration + rank-aggregation design | COMBINER | corpus KG/network registries; virtual-KO screen; `gold_targets_*` in S3 | `W6_combiner_inventory.*` |
| **W7** | Tier-2 paired-atlas feasibility — count (cell-context × perturbation × HLA-genotype) triples with ≥2 modalities. THE #1 GAP; decides FM-training feasibility | FEASIBILITY | PAIRED_SAMPLE_INVENTORY, MODALITY_* manifests, immunopeptidome/ribo/proteome, CZI perturb-seq | `W7_tier2_paired_atlas.*` |
| **W8** | Derived-score → validation-dataset map — each FM derived score (durability, irAE/neo-presentation, tolerance epitopes, causal-epitope rank) → which dataset validates it → what's still missing | VALIDATE | OBJECTIVES §3.2; W1–W4 outputs | `W8_derived_score_validation_map.*` |

## Dependencies
- W8 synthesizes W1–W4 (run last / with their partial outputs).
- W1 and W7 are the decisive feasibility gates — if paired-N is near zero for an objective,
  no downstream build is justified; log that explicitly (no silent truncation).
- W2/W3/W4/W5 are independent data assembles; W6 is independent inventory.

## What "one model" means (resolved)
ONE mechanistic FM (H1–H4 + bottleneck). The 7–8 "objectives" are produced by the
surrounding system (combiner + gates + derived scores) + external validation — NOT by
one model with 8 clinical heads. Direct clinical-outcome prediction remains a non-goal
unless the spec is deliberately amended.
