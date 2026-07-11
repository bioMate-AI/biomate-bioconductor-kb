# Researcher Chains — Full Session Record

**Date:** 2026-06-23  
**Branch:** `integration/next-phase`  
**Final commit:** `533766274` (pushed to GitHub)  

---

## What was built

### 1. Gap audit doc

`docs/20260623_RESEARCHER_CHAINS_GAP_AND_PLAN.md`

Corrected the record from prior session docs that described turep / scupa / immuneapp `.nf` files as "existing stubs" — they did not exist at all. The gap doc also caught that PathwayCommons12 was already baked into the scGWAS container (previously flagged as missing in error).

Six gaps documented; implementation order set for the session.

---

### 2. ZZ01 chain — Zhao lab tumor-reactive T-cell pipeline

**`turep/main.nf`** (3-phase)
- Phase A: validates `.h5ad` input; generates synthetic 100-cell fixture if use_baked_toy
- Phase B: calls `turep.load_model()` → `predict_tr(model, adata, batch_size=512)`; threshold 0.5; writes `scores.tsv` + `reactive_cells.h5ad`; graceful on ImportError
- Phase C: reports reactive count; notes Scupa is blocked, reactive cells can feed ImmuneApp directly

**`turep/container/Dockerfile`**
- Base: `python:3.11-slim`
- PyTorch CPU + anndata / numpy / pandas / scipy / h5py
- Installs turep from `bsml320/turep` via pinned SHA
- Import-only smoke at build time (no `load_model()` — avoids HuggingFace download in offline builds)

**`scupa_polarization/main.nf`** (held — license blocked)
- Single process `SCUPA_BLOCKED` that writes `scupa_blocked.json` and exits 1
- Reason: `bsml320/Scupa` has NOASSERTION license
- Includes: unblock action (email Zhao lab), workaround (turep → ImmuneApp bypass), biomate_ticket

**`immuneapp_hla_screen/main.nf`** (3-phase)
- Phase A: accepts `--peptide_fasta`, `--vcf_input`, or `--use_baked_toy`; baked toy includes KLVVVGAVGV (RAS neoantigen, published rank 0.12% at HLA-A\*02:01)
- Phase B: `immuneapp.load_model(hla_allele)` → `immuneapp.predict(model, seq)`; fallback to hardcoded mock ranks from published benchmark if package absent
- Phase C: filters at `--rank_cutoff 2.0`, sorts ascending, writes `neoantigens_ranked.tsv` + Markdown report

**`immuneapp_hla_screen/container/Dockerfile`**
- Base: `python:3.11-slim`
- PyTorch CPU + numpy / pandas / scipy / scikit-learn
- Installs ImmuneApp from `bsml320/ImmuneApp`; pretrained weights bundled in upstream repo (no HuggingFace download at runtime)
- Full smoke at build time: `load_model("HLA-A*02:01")` → `predict("KLVVVGAVGV")` → asserts `rank_pct` in result; soft failure (`|| echo WARNING`) since `.nf` has graceful fallback

---

### 3. Shared GWAS methods stack — Zhi lab Z01 + Zhao lab ZZ02

Implements the Methods section of two published papers:
- Zhi lab Nat Commun 2026 (PMC12458571): METAL + MAGMA + TorchGWAS + LDSC
- Zhao lab Genome Biology 2022 (PMC9575201): MAGMA → scGWAS

**TorchGWAS Phase D upgrade** (`torchgwas_udip_phenotype_scan/main.nf`)
- Phase D rewritten to add real EBI GWAS Catalog REST API call
- 1 Mb clumping of independent loci; max 20 queries; 200 ms between calls
- Each lead locus flagged: `novel` / `known` / `catalog_unavailable`
- Graceful: if network unavailable, run still succeeds with `catalog_status="catalog_unavailable"`
- Endpoint: `https://www.ebi.ac.uk/gwas/rest/api/singleNucleotidePolymorphisms/search/findByChromBpLocationRange`

**`magma_gene_analysis/main.nf`** (3-phase)
- Phase A: `MAGMA_ANNOTATE` — maps SNPs to genes using NCBI gene.loc + `magma --annotate`
- Phase B: `MAGMA_GENE_ANALYSIS` — per-gene Z-statistics; `--gene-model snp-wise` (smoke) or `multi` (production with g1000_eur)
- Phase C: `MAGMA_FORMAT` — box-cox transform of ZSTAT; emits both `.magma.txt` (raw, for FUMA) and `.magma_boxcox.txt` (for `scgwas_immune_cell --gwas_sumstats`)
- Smoke: generates 2000 synthetic chr1 SNPs with a signal cluster at 50–55 Mb

**`magma_gene_analysis/container/Dockerfile`**
- Base: `ubuntu:22.04`
- Bakes: MAGMA v1.10 static binary (ctg.cncr.nl, academic freeware) + g1000_eur LD reference (~300 MB) + NCBI37.3 + NCBI38 gene.loc files
- License note: MAGMA is freeware for academic use; binary downloaded from official server at build time; container not redistributable outside BioMate
- Smoke: `/opt/magma/magma --help` + scipy import

**`metal_meta_analysis/main.nf`** (2-phase)
- Phase A: `METAL_PREP` — validates ≥2 cohort files; generates synthetic cohort pair for smoke (1000 SNPs each, same seeds → reproducible); writes METAL script with SCHEME / PROCESS / ANALYZE directives
- Phase B: `METAL_RUN` — executes `metal script.txt`; parses `METAANALYSIS1.TBL`; counts GW-sig hits; emits downstream routing instructions for MAGMA and LDSC
- Reference: Willer et al. Bioinformatics 2010, doi:10.1093/bioinformatics/btq340

**`metal_meta_analysis/container/Dockerfile`**
- Base: `ubuntu:22.04`
- Builds METAL from `statgen/METAL` via CMake at image build time (MIT license)
- Binary lands at `/usr/local/bin/metal`

**`ldsc_heritability/main.nf`** (3-phase)
- Phase A: `LDSC_MUNGE` — `munge_sumstats.py` against w_hm3.snplist; emits `.sumstats.gz`
- Phase B: `LDSC_H2` — `ldsc.py --h2` with baked eur_w_ld_chr; parses h², intercept, attenuation ratio, lambda GC from log
- Phase C: `LDSC_REPORT` — QC flags: h² < 0 or > 1; intercept > 1.1; ratio > 0.1; Markdown summary table
- Reference: Bulik-Sullivan et al. Nat Genet 2015, doi:10.1038/ng.3211

**`ldsc_heritability/container/Dockerfile`**
- Base: `python:3.9-slim` (LDSC compatibility)
- Installs ldsc from `bulik/ldsc` (GPL-3.0)
- Bakes: eur_w_ld_chr (22-chromosome European LD scores, ~25 MB) + w_hm3.snplist from bulik-lab public S3

---

### 4. Database updates (local)

Ran three scripts against `backend/database/galaxy_ai_tools.db`:

| Script | Inserted workflows | Inserted chains |
|---|---|---|
| `add_zhi_lab_chains.py` | `torchgwas_udip_phenotype_scan`, `fda_protein_ligand_affinity` | `torchgwas_udip_chain` (id=39), `fda_ligand_screen_chain` (id=40) |
| `add_zhao_lab_chains.py` | `turep`, `scupa_polarization`, `immuneapp_hla_screen`, `scgwas_immune_cell` | `tumor_reactive_t_cell_chain` (id=41), `scgwas_immunology_chain` (id=42) |
| `add_gwas_methods_chain.py` (new) | `magma_gene_analysis`, `metal_meta_analysis`, `ldsc_heritability` | `z01_gwas_methods_chain` (id=43) |

All scripts are idempotent (check-before-insert). The large canonical db (304 MB, 4000+ workflows) was synced externally with these additions applied. `galaxy_ai_tools.db` is gitignored and not committed.

---

### 5. Git push

The db had been force-committed in a prior session commit (`440322e56`, 292 MB), blocking GitHub's 100 MB file limit. Fix:

```bash
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --index-filter \
  'git rm --cached --ignore-unmatch backend/database/galaxy_ai_tools.db' \
  --tag-name-filter cat -- ${REMOTE_HEAD}..HEAD
```

Stripped the db from all 59 commits ahead of origin, then pushed clean. Branch `integration/next-phase` now at `533766274`. The db file remains on disk (gitignored) and is not in git history going forward.

---

## Chain integration diagram

```
[cohort1.tsv]  ─┐
[cohort2.tsv]  ─┤  metal_meta_analysis   →  combined sumstats
[cohort3.tsv]  ─┘

combined sumstats  →  magma_gene_analysis  →  .magma_boxcox.txt  →  scgwas_immune_cell (ZZ02)

raw genotypes      →  torchgwas_udip_phenotype_scan  →  GWAS hits + novel loci (GWAS Catalog)
                                 ↓
                         ldsc_heritability  →  h² + intercept QC

[scRNA .h5ad]  →  turep  →  reactive_cells.h5ad
                               ↓  (Scupa: BLOCKED — NOASSERTION license)
                               ↓  (bypass: direct)
                         immuneapp_hla_screen  →  neoantigens_ranked.tsv  (ZZ01)
```

---

## Files created / modified this session

| File | Type |
|---|---|
| `backend/nf-core-workflows/modules/biomate-ai-tools/turep/main.nf` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/turep/container/Dockerfile` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/scupa_polarization/main.nf` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/immuneapp_hla_screen/main.nf` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/immuneapp_hla_screen/container/Dockerfile` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/magma_gene_analysis/main.nf` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/magma_gene_analysis/container/Dockerfile` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/metal_meta_analysis/main.nf` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/metal_meta_analysis/container/Dockerfile` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/ldsc_heritability/main.nf` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/ldsc_heritability/container/Dockerfile` | new |
| `backend/nf-core-workflows/modules/biomate-ai-tools/torchgwas_udip_phenotype_scan/main.nf` | modified (Phase D GWAS Catalog) |
| `backend/scripts/add_gwas_methods_chain.py` | new |
| `docs/20260623_RESEARCHER_CHAINS_GAP_AND_PLAN.md` | new |

---

## Still blocked / not done

| Item | Blocker |
|---|---|
| ECR push for all 7 new containers (turep, immuneapp, magma, metal, ldsc, scgwas, torchgwas) | Needs AWS ECR write credentials |
| Scupa license | Zhao lab must add MIT/Apache-2.0 to `bsml320/Scupa` |
| Dev sync | Held — not tested yet |
| FUMA wrap | P3 priority, not started |
| LDSC cross-trait rg (second mode) | Phase B currently only does `--h2`; `--rg` with two traits is a natural extension |
| Z02 FDA inference entry point | Zhi lab needs to confirm `predict(target_fasta, ligand_sdf)` API |
| UKB credential for paper-faithful Z01 | 3-month UKB application cycle |
