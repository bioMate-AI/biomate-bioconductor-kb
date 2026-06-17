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

**Implication for the demo recording schedule:** ZZ02 + Z01 can record real-data demos within 1–2 weeks. The Zhi-lab Z02 demo + Zhao-lab ZZ01 full-chain demo are ≥1 month out; record stub-data versions of those for pitch material in the interim.

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
