# ANDV Three Tracks — Status, Findings, and Execution Plan

**Date:** 2026-06-03  
**Publication run:** `research/anti-virus/runs/publication_20260528T223525Z`  
**Inhibitor reference run:** `research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z`

---

## Executive summary

| Track | Consolidated? | Publication-ready? | Wet-lab-ready? |
|-------|---------------|-------------------|----------------|
| **Plan A** (epitope) | Yes | Almost — figures regen + manuscript polish | **Yes** — peptide order list |
| **Plan B** (mRNA/LNP) | Partial | Draft exists; needs unified bundle | **Spec now in** `plan_b_wet_lab/PLAN_B_WET_LAB_SPEC.md` |
| **Inhibitor** | Partial (manifest updated) | Docking + MD + MM-GBSA OK | Shortlist; INH-01 medchem gate |

---

## Plan A — epitope / protein vaccine

### Findings (consolidated)

| Artifact | Value |
|----------|-------|
| MHCnuggets | 45,160 rows; 113 binders |
| MHCflurry | 809 binders; 545 unique peptides |
| Merged multitool TSV | 90,320 rows; 604 unique binder peptides |
| Conservation | 54 triple-species 9-mers; 10 overlap with binders |
| Wet-lab package | `wet_lab_package/WET_LAB_CANDIDATES.md` — MB-01…15, XSP-01…15 |

### Remaining

1. Manuscript v1.1 author/refs/outbreak framing (`FEEDBACK_CROSSWALK.md` Phase 1)
2. Figure regeneration from full GP TSV (script updated; run `generate_manuscript_plan_a_figures.py`)
3. Optional: NetMHCpan/MixMHC; conformational epitope track

### Wet lab (ready)

- **Track A:** 15 MHC-validated peptides → DimerX/ELISA → ELISpot  
- **Track B:** 15 conserved 9-mers (4 HIGH: XSP-09/10/11/15)

---

## Plan B — mRNA / LNP

### Findings (compute complete, artifacts scattered)

| Step | Metric | Artifact |
|------|--------|----------|
| Codon opt | 737/1138 codons (64.76%) | `plan_b_codon/` |
| RNA2D 5′ | MFE −182.7 kcal/mol | `plan_b_rna2d/` |
| LNP | EE 20%; escape 0.202; pKa SUBOPTIMAL | `plan_b_lnp/lnp_results.json` |
| P0 ANDV | overall_pass: true, CAI 1.0 | `plan_b_p0/andv_p0_mrna_validation_report.json` |
| P0 spike 12819 | overall_pass: true | `plan_b_p0/spike_12819/` |
| NP-PK | t½ 1.9 h; stealth POOR | `plan_b_np_pk/np_pk_results.json` |

### Consolidation deliverable

**`plan_b_wet_lab/PLAN_B_WET_LAB_SPEC.md`** — CRO-facing synthesis spec (CDS, construct, LNP, PK caveats).

### Remaining

1. Download optimized CDS from S3 to local FASTA (Batch outdir)
2. LNP reformulation (pKa too basic for endosomal ionization)
3. Manuscript v1.1 finalization + Fig C5 cross-link
4. Product E2E PB-1…5 (not blocking wet lab)

---

## Inhibitor — structure-guided small molecule

### Findings

| Step | Status | Notes |
|------|--------|-------|
| Pocket → pharmacophore → ADMET → Vina | Succeeded | Run `20260513T032000Z` |
| REINVENT4 | Succeeded | 0 compounds retained after filters |
| ZINC150 screen | Succeeded | 145 docked; best **−6.267 kcal/mol** (INH-01) |
| Ensemble top-5 | Done | 1/5 improved vs rigid |
| Ensemble top-15 | Failed | Polling artifact; 0/15 improved |
| GROMACS INH-01 MD | **Done** | Run `28fd9a07`; RMSD ~0.41 nm |
| MM-GBSA | **Done** | **ΔG_bind −10.49 ± 0.46 kcal/mol** (19 frames, GB igb=2; job `ffc49896`) |
| Aspirin GROMACS | Partial | Prep/EM only |

### Fixes applied (2026-06-03)

- `pipeline_manifest.json` backfilled with GROMACS steps  
- `ambertools-gromacs-nf` Dockerfile **v1.2.0**: `openmpi`, `mpi4py`, `gmx_mmpbsa` — **pushed to ECR**  
- MM-GBSA standalone Batch job **`ffc49896`**: INH-01 **ΔG_bind −10.49 kcal/mol**  
- `gromacs_protein_md` `MM_GBSA` process: index groups, frame range, ΔTOTAL parser  
- Wet-lab shortlist rebuilt from ZINC150 Vina JSON (Track C in `wet_lab_package/`)

### Remaining (priority)

1. Update inhibitor manuscript with ZINC150 + MD + MM-GBSA numbers  
2. Medchem ADMET review for INH-01 before synthesis order  
3. Aspirin control MD (optional benchmark)  
4. Retry top-15 ensemble with fixed polling

---

## Parallel execution plan (this session)

| # | Task | Owner | Status |
|---|------|-------|--------|
| 1 | Master status doc (this file) | Agent | Done |
| 2 | Plan B wet-lab spec | Agent | Done |
| 3 | Refresh `PUBLICATION_STATUS.md`, `FEEDBACK_CROSSWALK.md` | Agent | Done |
| 4 | Backfill inhibitor manifest | Agent | Done |
| 5 | ECR Dockerfile v1.2.0 (OpenMPI) | Agent | Done — pushed to ECR |
| 6 | Regenerate Plan A figures (full GP) | Agent | Done |
| 7 | Rebuild wet-lab package (ZINC150 hits) | Agent | Done |
| 8 | Submit MM-GBSA Batch job | Agent | Done — `ffc49896`, ΔG −10.49 kcal/mol |

### ECR rebuild commands

```bash
cd backend/docker/ambertools-gromacs-nf
docker build --platform linux/amd64 -t biomate/ambertools-gromacs-nf:1.2.0 .
aws ecr get-login-password --region us-west-2 | docker login --username AWS \
  --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
docker tag biomate/ambertools-gromacs-nf:1.2.0 \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest
docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest
research/anti-virus/scripts/run_mmgbsa_standalone_batch.sh
```

---

## Readiness gates

### bioRxiv deposit (per track)

- **Plan A:** After figure regen + author fill-in  
- **Plan B:** After Plan B spec review + LNP caveat in abstract  
- **Inhibitor:** After MM-GBSA ΔG or explicit “MD stability only” scope  

### Wet lab go/no-go

- **Plan A:** **GO** — order peptides  
- **Plan B:** **GO with caveats** — use spec; reformulate LNP before animal PK claims  
- **Inhibitor:** **HOLD** synthesis until MM-GBSA + medicinal chemistry review (INH-01 DILI 0.643 in ADMET)

---

## Related docs

- [`SESSION_20260602_GROMACS_HPC_INFRA.md`](../research/anti-virus/runs/publication_20260528T223525Z/SESSION_20260602_GROMACS_HPC_INFRA.md)
- [`20260529_ANDV_THREE_TRACKS_REMAINING_WORK.md`](./20260529_ANDV_THREE_TRACKS_REMAINING_WORK.md)
- [`PUBLICATION_STATUS.md`](../research/anti-virus/runs/publication_20260528T223525Z/PUBLICATION_STATUS.md)
