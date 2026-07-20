# Biomedical Model Training — Session Work Log, Results & Plan (2026-07-19)

Single source of truth for the autoimmune + cyclic-peptide model-training workstream.
All compute is EC2, all storage is S3 (`s3://knowledge-datasets-1759951976/…`); local is not used for heavy work. Instances self-terminate. Total spend so far ≈ **$5–7**.

---

## 1. Strategic decision (recap)
- **Narrow-first, adopt-don't-build.** Don't pretrain a broad public-data foundation (undifferentiated; competitors have more cells/GPUs). Adopt existing foundations; spend effort on tailored adaptation + curated-corpus depth + the orchestration flywheel.
- **Two disease-facing tracks, one loop:** autoimmune single-cell (SLE-first) = **target selection**; **cyclic peptides (环肽)** = **binder design** with a **macrocycle-specific ADMET moat**. Elevated the cyclic-peptide ADMET model **ahead of** the SLE FM (cleaner labels, clearer gap, direct design value).
- Base-model calls (from the deep survey): orchestration LLM = **Qwen3-14B** (not Llama 3.1 70B); sc = adopt **CellFM/scGPT-blood** (Geneformer for stratification only); every model behind a **linear baseline gate**.

## 2. Work log — what was built & run this session

**Automated data-collection harness (EC2→S3), all self-terminating:**
- `research/autoimmune_corpus/` — discovery (NCBI E-utils), Census acquisition (`cellxgene_census`), harmonization (patient-split), source-pub mapping, SLEDAI extraction, baseline gate; cyclic-peptide collector + baseline.
- Dedicated IAM role/profile `AutoimmuneCorpusRole/Profile` (SSM + scoped S3 write to `autoimmune_sc_corpus/*` and `cyclic_peptide/*` + ECR pull of `biomni-admet`).

**Delivered artifacts (in S3):**
- **Discovery manifest** — 174 autoimmune scRNA series (SLE/RA/IBD/MS), 139 with linked PMIDs.
- **Autoimmune sc corpus** — `curated/autoimmune_sc_corpus.h5ad`: **1,288,126 cells × 47,594 genes, 6,335 donors**, 5 groups (SLE 500K, Healthy 497K, IBD 243K, RA 38K, MS 11K), patient-split.
- **Source-pub map** — every dataset → DOI; **SLE = Perez 2022 *Science*** (`science.abf1970`).
- **SLEDAI labels** — Perez original `obs` has per-donor **`disease_state`**; 261-donor activity table in `labels/baseline/SLE_donor_activity.csv`.
- **CycPeptMPDB** — `cyclic_peptide/raw/CycPeptMPDB_Peptide_All.csv`: **8,466 cyclic peptides**, permeability target `Same_Peptides_Permeability`.

**Deep survey + planning docs (see §7).**

## 3. Baseline-gate results (both ran 2026-07-19)

### SLE sc baseline — RAN ✅ (one fix needed)
| Metric | Value |
|---|---|
| PCA+LR cross-disease macro-F1 | **0.419** |
| per-class F1 | Healthy **0.96**, SLE **0.68**, RA 0.40, IBD 0.05, MS n/a |
| mean-centroid macro-F1 | 0.095 |
| IFN score | **not computed** — bug (below) |

**Read:** big classes are linearly separable (Healthy/SLE), but rare autoimmune classes are **donor-starved** (IBD 25, RA 18, MS 5 donors) and the "Healthy" pull massively dominates (6,129 donors) — macro-F1 is dragged by the tail. **The decisive gate (IFN / activity stratification) did not run** because the corpus `var_names` are Ensembl IDs and the IFN gene *symbols* didn't match. → **Fix: map via `adata.var['feature_name']`.** Also: rebalance / cap Healthy donors and pull more RA/IBD/MS donors for a fair categorical read.

### Cyclic-peptide permeability baseline — dataset ✅, baseline FAILED (fix)
- CycPeptMPDB downloaded and parsed (8,466 rows; SMILES + permeability columns found).
- **Descriptor step parsed 0 peptides** — `rdkit MolFromSmiles` returned None for all (macrocycle sanitization) → `feat[DESC]` KeyError. → **Fix: use CycPeptMPDB's own precomputed numeric descriptor columns** (robust, avoids re-parsing), with an rdkit `sanitize=False` fallback as secondary.

## 4. Two fixes queued (then re-run both, parallel)
1. **SLE baseline:** locate IFN genes via `adata.var['feature_name']`; add Healthy-donor cap + report SLE-vs-Healthy and (once SLEDAI joined) low/high activity AUC vs Perez R=0.66.
2. **Cyclic-peptide baseline:** feature from the CSV's numeric descriptor columns; report permeability R²/RMSE (ridge/RF) + Yudin pass-rate. This is the go/no-go for a learned macrocycle model.

## 5. The plan (phased; parallel streams)

| Phase | SLE / autoimmune track | Cyclic-peptide track (elevated) | Where |
|---|---|---|---|
| A Data prep | ✅ 1.29M-cell corpus + SLEDAI labels | ✅ CycPeptMPDB (8,466) | EC2→S3 |
| B Baseline gate | ⟳ rerun (IFN fix) → activity vs R=0.66 | ⟳ rerun (descriptor fix) → permeability R² | EC2 (+biomni-admet ECR) |
| C Model (if gate clears) | A+B multi-task FT on CellFM/scGPT-blood | **macrocycle ADMET/permeability model** (priority) | EC2/Spark |
| D Integration | target selection → | → design (CyclicMPNN/AlphaFold3/Boltz) → macrocycle-ADMET gate → dock vs voclosporin | GPU burst |

**Execution rules:** rdkit/cheminformatics via `biomate/biomni-admet` ECR image; single-cell via pip (scanpy/cellxgene-census); structure/design (AlphaFold3/Boltz) needs **cloud H100 burst** (not the Spark); orchestration LLM (Qwen3-14B LoRA) is a separate background track on the already-executed validation traces.

**Baseline-gate discipline (non-negotiable):** ship a learned model only if it beats the linear baseline — sc activity must beat Perez R=0.66; macrocycle model must beat the descriptor R².

## 6. Live infra state
- Instances: both baseline instances **terminated** (self-cleaned). IAM role/profile + S3 layout persist for reruns.
- S3 layout:
  - `autoimmune_sc_corpus/` → `curated/`, `raw/`, `labels/`, `logs/`, `code/`
  - `cyclic_peptide/` → `raw/`, `baseline/`, `logs/`
- ECR image: `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-admet:x86-9024d7ece990`.

## 7. Detailed companion docs (this workstream)
- `20260718_LLM_TRAINING_DEEP_SURVEY.md` — 4-survey base-model + moat assessment.
- `20260718_LLM_TRAINING_ROADMAP_v2.md` — re-based 4-layer plan (Qwen3-14B, etc.).
- `20260718_LAYER4_TRACE_CORPUS_BUILD_SPEC.md` — orchestration-LLM trace corpus.
- `20260719_AUTOIMMUNE_MODEL_TRAINING_STRATEGY_AND_DGX_EXECUTION.md` — narrow-first strategy + DGX/EC2 plan.
- `20260719_AUTOIMMUNE_CORPUS_AUTOCOLLECTION_PLAN.md` — the 3-layer collector.
- `20260719_CYCLIC_PEPTIDE_MODALITY_TRACK.md` — cyclic-peptide track (moat, loop, dataset, model).
- (this) `20260719_MODEL_TRAINING_SESSION_STATUS_AND_PLAN.md` — index + results + plan.

## 8. Open decisions / risks
- **Healthy-donor imbalance** in the sc corpus (6,129 vs 158 SLE donors) — cap Healthy + pull more RA/IBD/MS before the categorical read is fair.
- **Activity gate not yet run** — the real SLE go/no-go (beat Perez R=0.66) is pending the IFN fix + SLEDAI join.
- **Macrocycle SMILES parsing** — rely on CycPeptMPDB precomputed descriptors; rdkit macrocycle sanitization is unreliable.
- **Structure/design needs GPU burst** — budget a cloud H100 run only after the permeability gate clears.
