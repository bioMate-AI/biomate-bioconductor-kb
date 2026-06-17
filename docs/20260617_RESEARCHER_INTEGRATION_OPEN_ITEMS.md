# Researcher Integration — Open Items for Real-Data Validation

**Date:** 2026-06-17
**Context:** Zhi-lab + Zhao-lab chain wirings completed today. Backend metadata layers (chains 69/70/71/72, qc_evidence citations, rationale_registry rows) are populated and **verified live** via `researcher-chains-audit.e2e.ts` (4/4 @meta tests pass against Galaxy :8081 + Node :5000). The .nf workflows currently emit **placeholder JSON** — they exercise the chain plumbing but do not run the actual research code.

This doc enumerates the work needed to swap stubs for real implementations and validate end-to-end with real datasets.

## Per-chain open items

| Chain | Workflow(s) | Upstream code | Test dataset needed | Compute |
|---|---|---|---|---|
| **Z01** torchgwas_udip_chain | torchgwas_udip_phenotype_scan | github.com/ZhiGroup/TorchGWAS (MIT, Python+PyTorch) | UDIP-derived FA phenotype CSV (256 cols × ~40k samples) + PLINK bed/bim/fam (UKB subset) | 1× A100 (~2h) |
| **Z02** fda_ligand_screen_chain | fda_protein_ligand_affinity | github.com/ZhiGroup/FDA (MIT) | EGFR T790M sequence (UniProt P00533 698–1022) + 1000-compound SMILES list (DrugBank approved subset) | 1× A100 (~30 min) |
| **ZZ01** tumor_reactive_t_cell_chain | turep + scupa_polarization + immuneapp_hla_screen | github.com/bsml320/{turep, Scupa, ImmuneApp} | Public melanoma 10x PBMC h5ad (~10k cells) + HLA-A*02:01 candidate peptides | 1× A100 (~45 min, 3 sequential steps) |
| **ZZ02** scgwas_immunology_chain | scgwas_immune_cell | github.com/bsml320/scGWAS (GPL-3.0, Java) | Crohn's disease GWAS Catalog sumstats + gut single-cell atlas (Smillie 2019 or similar) | 1× CPU node (~15 min) |

## License blockers

- **Scupa** (`bsml320/Scupa`) — NOASSERTION. Required for ZZ01 Step 2. Either:
  1. Email the Zhao lab to request MIT/Apache license addition, OR
  2. Re-implement the polarization scoring logic in BioMate using their published method (gene-set scoring with cell-type marker panels) — feasible since the underlying biology is public.

- **Other Tier-B Zhao tools** (NetRNApan, BrainGeneBot, GENEVIC, CancerGen-RAG, VAEN, DeepTR, etc.) — no LICENSE files. Bulk-ask in the outreach email.

- **Tier-B Zhi tools** (SLAB, Syllable-PBWT, bi-PBWT, FastRecomb, IBD-Booster, P-smoother, ROH-DICE, HiFiMAP, pytorch_ehr, CovRNN, PK-RNN, UDIP-FA, UDIP-MoCoV2, UDIP-replicability) — no LICENSE files.

## Implementation order recommendation

Priority by demo impact + technical ease:

1. **Z02 (FDA)** — single-tool MIT-licensed, models already shipped with weights, fast (~30 min). **First real-data demo.**
2. **ZZ02 (scGWAS)** — single-tool GPL-3.0, Java (no GPU needed), fast (~15 min). Second.
3. **Z01 (TorchGWAS+UDIP)** — single-tool MIT but requires UKB access for the UDIP phenotypes. **Blocker:** UKB credential.
4. **ZZ01 (3-step chain)** — most complex (license + 3 tools + chain orchestration). **Defer until Scupa license clarified.**

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
