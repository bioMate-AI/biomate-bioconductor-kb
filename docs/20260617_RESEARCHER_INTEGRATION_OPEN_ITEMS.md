# Researcher Integration — Open Items for Real-Data Validation

**Date:** 2026-06-17
**Context:** Zhi-lab + Zhao-lab chain wirings completed today. Backend metadata layers (chains 69/70/71/72, qc_evidence citations, rationale_registry rows) are populated and **verified live** via `researcher-chains-audit.e2e.ts` (4/4 @meta tests pass against Galaxy :8081 + Node :5000). The .nf workflows currently emit **placeholder JSON** — they exercise the chain plumbing but do not run the actual research code.

This doc enumerates the work needed to swap stubs for real implementations and validate end-to-end with real datasets.

## Per-chain open items — README-verified 2026-06-17

Repo recon revealed the four tools are NOT equally ready. Updated table:

| Chain | Wrap effort | README state | Test data |
|---|---|---|---|
| **Z01 TorchGWAS** | **EASY — 2–3 days** | Single `pip install -e .`, single CLI (`torchgwas linear`), toy dataset shipped at `examples/toy/` (genotype.npy + pheno.tsv + covar.tsv). Genuinely production-ready inference path. | Use shipped toy dataset for smoke; UKB sumstats blocked on credential. |
| **ZZ02 scGWAS** | **EASY — 2 days** | Single `java -jar scGWAS_r0.jar configure.txt`. Repo ships 18 pre-processed scRNA panels + a runnable `example/` folder. No GPU. | Shipped example; later add Crohn's GWAS Catalog sumstats. |
| **ZZ01 turep (Step 1 only)** | **MEDIUM — 3–5 days** | Python API only (`load_model() → predict_tr()`), no CLI. Pretrained weights auto-download on first run. No example data in main repo (separate `turep_notebooks` repo has it). | Need a public PBMC h5ad. |
| **ZZ01 Scupa** | **BLOCKED — license** | NOASSERTION — re-license or re-implement. | — |
| **ZZ01 ImmuneApp** | MEDIUM — 3–5 days | MIT, separate repo + paper. Examine before committing. | — |
| **Z02 FDA** | **HARD — 2–3 weeks, currently NOT recommended** | Two conda envs (Python 3.10 + CUDA 12.3 for folding, Python 3.9 + CUDA 11.5 for docking/affinity). Entry points are TRAINING scripts (`train_GIGN_benchmark.py`), not a clean inference CLI. No example data in repo — Zenodo download required. README describes how to reproduce the paper, not how to predict for a new pair. | Need a custom inference wrapper built before wrap is viable. |

**Corrected priority order** (was: Z02 → ZZ02 → Z01 → ZZ01; **now**: ZZ02 → Z01 → turep alone → Z02 deferred):

1. **ZZ02 scGWAS** — single Java jar, shipped example, no GPU. **First real-data demo.** Days.
2. **Z01 TorchGWAS** — single CLI, shipped toy dataset. Second. Days.
3. **ZZ01 turep only** (not the full 3-step chain) — wrap the `predict_tr()` Python API as a single workflow. Stub Scupa + ImmuneApp until later. ~1 week.
4. **Z02 FDA** — **defer until a clean inference entry point exists.** Reach out to Zhi lab asking: "do you have a `predict(target_fasta, ligand_sdf) → affinity` function we can call, or do we need to build the inference wrapper ourselves?" If yes → ~3 days; if no → ~3 weeks.

**Implication for the demo recording schedule:** ZZ02 + Z01 can record real-data demos within 1–2 weeks. **Z02 (FDA) is dropped from the integration backlog** — the README is a paper-reproduction recipe (2 conda envs, no inference CLI, no example data). Revisit only if Zhi lab provides a clean `predict(target, ligand)` function. The Zhao-lab ZZ01 full-chain demo is ≥1 month out (Scupa license + 3-tool orchestration); record stub-data version for pitch material in the interim.

## Verified test data — from the actual papers

Looked up each paper's published-cohort / shipped-example to ground the real-data demos:

### Z01 — TorchGWAS + UDIP (medRxiv 2025.07.04.25330856; PMC12458571)

> "Trained an unsupervised deep neural network using FA images from **6,000 UK Biobank participants** to derive a 128-dimensional representation (UDIP-FAs). A GWAS was performed on the UDIP-FAs using **25,875 UKB participants**. Explored genetic associations and causal effects associated with **24 brain disorder traits**."

- **TorchGWAS-only smoke test (today):** shipped `examples/toy/` — 64 samples × 12 variants × 3 phenotypes × 4 covariates. Tiny but runs the full preprocessing + LMM solver. Sufficient to prove the wrap works end-to-end.
- **Realistic-scale demo without UKB credential:** 1000 Genomes Phase 3 (2,504 samples, ~80M variants, fully open) + simulated quantitative phenotypes drawn from a small heritable component. Demonstrates the GPU scaling claim without UKB gating. ~30 GPU-min for 256 phenotypes × 80M variants.
- **Paper-faithful demo (requires UKB approval):** 25,875 UKB participants × 256 UDIP-FA phenotypes × UKB imputed variants. Recovers the paper's headline findings (e.g. HFE/HLA region). UKB application cycle is ~3 months — defer.
- **UDIP-FA encoder data (Phase A):** the lab's encoder was trained on the UKB 6,000-subject FA cohort. For an open-data analog, **Human Connectome Project** (1,200 subjects, FA maps available) is the closest, but the encoder may not transfer without retraining. For the demo, use a **pre-computed UDIP-FA phenotype CSV** if the lab will share one, or just use a synthetic 256-column phenotype matrix labeled "UDIP_FA_001…256" and disclose it in the tip card.

### ZZ02 — scGWAS (Jia et al., Genome Biology 2022, PMC9575201)

> "Demonstrated scGWAS in **40 GWAS datasets (avg N ≈ 154,000)** using **18 scRNA-seq datasets from 9 major human/mouse tissues (totaling 1.08 million cells)** and identified **2,533 trait × cell-type associations.**"

- **All test data ships with the repo.** `bsml320/scGWAS/example/` plus the 18 pre-processed scRNA panels in the repo cover every demo we'd want. No download, no UKB, no GPU.
- **Suggested demo trait:** Schizophrenia × pyramidal neurons (iconic published result) or Crohn's disease × Tregs. Both are within the 2,533 documented associations and resonate clinically.
- **Compute estimate:** 1× CPU node, ~15 min for the full example. Runs locally without AWS.

### ZZ01 Step 1 — turep alone (bsml320/turep)

- **Pretrained weights auto-download on first run** via `load_model()`. No setup data needed.
- **Test dataset:** the lab maintains a separate `turep_notebooks` repo with example PBMC/tumor h5ad. Need to fetch one. Alternatively, **any public 10x melanoma scRNA dataset** (e.g. Sade-Feldman 2018, GEO GSE120575 — 16k cells, melanoma TILs) works because turep is a cross-cancer classifier.
- **Compute:** 1× GPU, ~15–30 min depending on cell count.

## Practical demo-data plan (week-by-week)

| Week | Action | Cost |
|---|---|---|
| 1 | Wrap **scGWAS** real-data using shipped `example/`. Record ZZ02 demo. | Dev time only, no GPU |
| 1 | Wrap **TorchGWAS** with shipped `examples/toy/` for smoke + 1000G + simulated phenotypes for realistic scale. Record Z01 demo (use synthetic UDIP-FA phenotype labels with disclosure tip). | ~30 GPU-min per run |
| 2 | Apply for UKB credential (parallel to demo work; for future paper-faithful demos) | Free, ~3 mo cycle |
| 3 | Wrap **turep alone** with Sade-Feldman GSE120575 (downloadable melanoma scRNA). Record a ZZ01-stub variant. | ~30 GPU-min |
| 4 | Outreach to both labs with the 3 working demos + ask for (a) Scupa license, (b) FDA inference entry-point, (c) UKB credential sponsorship if needed | — |

## License blockers

- **Scupa** (`bsml320/Scupa`) — NOASSERTION. Required for ZZ01 Step 2. Either:
  1. Email the Zhao lab to request MIT/Apache license addition, OR
  2. Re-implement the polarization scoring logic in BioMate using their published method (gene-set scoring with cell-type marker panels) — feasible since the underlying biology is public.

- **Other Tier-B Zhao tools** (NetRNApan, BrainGeneBot, GENEVIC, CancerGen-RAG, VAEN, DeepTR, etc.) — no LICENSE files. Bulk-ask in the outreach email.

- **Tier-B Zhi tools** (SLAB, Syllable-PBWT, bi-PBWT, FastRecomb, IBD-Booster, P-smoother, ROH-DICE, HiFiMAP, pytorch_ehr, CovRNN, PK-RNN, UDIP-FA, UDIP-MoCoV2, UDIP-replicability) — no LICENSE files.

## Implementation order recommendation

Superseded by README-verified table above. The original order (Z02 first) was based on my first impression of the FDA repo; the README reveals it's not a clean inference tool. **New order: ZZ02 → Z01 → turep → Z02 (deferred).**

## Per-workflow real-implementation checklist

For each `.nf` file under `backend/nf-core-workflows/modules/biomate-ai-tools/<name>/main.nf`:

1. Replace each Phase's `python3 - <<'PY'` block with a real call:
   - Z02 Phase A: `esmfold --sequence $params.target_seq --output target_structure.pdb`
   - Z02 Phase B: `python -m fda.dock --target target_structure.pdb --library $params.ligand_smi`
   - etc.
2. Update the process `container` directive to point at an ECR image with the dependency stack baked in:
   - `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/zhi-fda:v1` (build from Dockerfile in `containers/zhi-fda/`)
3. Add a real test dataset under `s3://biomate-test-data/researchers/<chain>/`.
4. Extend `researcher-chains-audit.e2e.ts`'s `@dispatch` block (currently `test.describe.skip`) with the dispatch + run assertions.
5. Run the full @dispatch suite against dev EC2.
6. Record the Claude design demo per `Zhi-Lab Demo Requirement.md` / `Zhao-Lab Demo Requirement.md`.

## Verified-today (no follow-up needed)

- 4 chain rows in `workflow_chains` (ids 69–72)
- 7 workflow rows in `workflows`
- 5 qc_evidence domains (3 Zhi gates × 3 phases + 2 Zhao chains' worth)
- 19 rationale_registry rows (8 Zhi + 12 Zhao) all `curated_by ∈ {zhi-auto-from-spec, zhao-auto-from-spec}` and `confirmed: true`
- `/api/rationale/<chain>:<phase>` returns real curated text for every chain × phase
- `/api/workflows/<wf>/citations` returns ≥1 DOI for every workflow
- `chain_meta.json` sidecar wired in `nextflow_executor.execute_nextflow` + `workflow_chain._compute_chain_meta` (auto-parses `// [Phase X]` markers from the `.nf` file's header)
- 4/4 `@meta` Playwright tests pass live

## Next-tier engineering proposal — model-card workflow type

Researchers ship `{model.pt, predict.py, requirements.txt, citation.bib}` → BioMate auto-wraps as a 1-step workflow with citation pre-filled. Turns "integrate a new lab tool" from days to hours. ~2-day prototype, would accelerate every future researcher integration after Zhi/Zhao.
