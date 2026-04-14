# Routing Benchmark Rebuild — 2026-04-07

## Problem

The `cross_domain_routing/queries.yaml` (88 queries) was entirely hand-authored by Claude without consulting real nf-core documentation. Specific errors found:

| ID | Old ground truth | Why it was wrong |
|---|---|---|
| rna_001 | `nf-core/rnaseq` for "differential expression analysis" | nf-co.re/rnaseq explicitly states it does NOT do DE statistics; `nf-core/differentialabundance` is correct |
| epi_012 | `nf-core/methylseq` for "Illumina 450K array" | methylseq handles bisulfite **sequencing**, not Illumina arrays; `nf-core/methylarray` is correct |
| prot_011 | `drug_discovery/structure_prediction_docking` for "AlphaFold2 structure prediction" | `nf-core/proteinfold` is the correct primary; drug_discovery is acceptable if docking is implied |
| sc_003–sc_009 | `nf-core/scrnaseq` for clustering/UMAP/trajectory queries | scrnaseq goes FASTQ→count matrix only; post-preprocessing analysis is not covered |
| All admet_* | Invented workflow names (pharmacogenomics_workflow, etc.) | These don't exist in the BioMate DB |
| var_* | `nf-core/sarek_germline` / `nf-core/sarek_somatic` | These are not real pipeline names; correct is just `nf-core/sarek` |

## Solution

Rebuilt from scratch using:
1. **Official nf-co.re documentation** — fetched live from `nf-co.re/<pipeline>` for 24 key pipelines
2. Correct workflow names verified against actual BioMate DB entries

## New Dataset Stats

- **File**: `evaluation/datasets/cross_domain_routing/queries.yaml`
- **Total queries**: 120 (was 88)
- **Unique correct_workflows**: 27 (all verified in DB)
- **Validation**: 0 issues (no self-referential disqualified, no missing fields)

### Domain distribution
| Domain | Queries | Key workflows |
|---|---|---|
| variant_calling | 17 | sarek, raredisease |
| epigenomics | 17 | chipseq, atacseq, cutandrun, methylseq, methylarray |
| rna_seq | 15 | rnaseq, differentialabundance, lncpipe |
| metagenomics | 13 | taxprofiler, mag, ampliseq |
| proteomics | 13 | proteomicslfq, diaproteomics, mhcquant, proteinfold |
| single_cell | 13 | scrnaseq, spatialvi |
| transcriptomics | 11 | rnafusion, differentialabundance, smrnaseq, lncpipe |
| drug_discovery | 9 | structure_prediction_docking, gromacs_protein_md, reinvent4_lead_design |
| genomics | 6 | nanoseq, hic |
| immunology | 6 | airrflow, mhcquant |

### Difficulty distribution
- **direct**: 76 (query clearly names technique)
- **adversarial**: 27 (confusable pairs — most important for quality measurement)
- **indirect**: 17 (biology described without naming technique)

### Key adversarial pairs covered
- `nf-core/sarek` vs `nf-core/raredisease` (somatic vs rare disease trio)
- `nf-core/rnaseq` vs `nf-core/differentialabundance` (preprocessing vs DE statistics)
- `nf-core/chipseq` vs `nf-core/atacseq` vs `nf-core/cutandrun`
- `nf-core/methylseq` (WGBS) vs `nf-core/methylarray` (450K/EPIC)
- `nf-core/taxprofiler` (classification) vs `nf-core/mag` (assembly+binning)
- `nf-core/proteomicslfq` (DDA) vs `nf-core/diaproteomics` (DIA)
- `nf-core/scrnaseq` vs `nf-core/spatialvi` (standard vs spatial single-cell)
- `nf-core/airrflow` vs `nf-core/scrnaseq` (immune repertoire vs whole transcriptome)

## Old Benchmark Autopsy (88-task result on old ground truth)

The 88-task run on the old benchmark completed in background (2362s). Overall score: **0.216** (20% accuracy). This number is not meaningful — it reflects the benchmark's wrong ground truth as much as it reflects routing quality.

Key finding from the run:
- `rna_seq` domain: 0.818 accuracy (only domain where old GT happened to be right)
- All other domains: 0.000–0.333 (mix of wrong GT + genuine routing failures)
- `scrna_seq`: 0.250 — but the 12 queries expected downstream analysis to route to scrnaseq (wrong)

## Files Changed

| File | Change |
|---|---|
| `evaluation/datasets/cross_domain_routing/queries.yaml` | Complete rewrite: 88→120 queries, authoritative GT |
| `evaluation/runners/run_routing.py` | Updated `DOMAINS` list to match new domain names |

## Next Steps

1. Run full 120-task benchmark: `python runners/run_routing.py --output results/routing_new_gt/`
2. Diagnose failures — now the scores will reflect real routing gaps, not benchmark errors
3. Fix BioMate intent misclassification for knowledge queries (separate task)
4. Add CellChat and other missing workflows to DB when users ask
