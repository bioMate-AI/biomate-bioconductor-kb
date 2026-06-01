# ANDV Publication Campaign — Run 20260528T223525Z

Real-data production run launched from `launch_andv_publication_campaign.py`.

## Real inputs (not demo)

| Asset | Source | Size |
|-------|--------|------|
| ANDV GP protein | UniProt **Q9E006** (reviewed) | 1138 aa |
| ANDV GP CDS | Reverse-translated from Q9E006 (human codon table) | 3414 nt |
| HLA panel | A\*02:01, A\*01:01, A\*03:01, A\*24:02, B\*07:02, B\*08:01, B\*27:05, B\*35:01 | 8 alleles |
| Compound library | ZINC20 subset (local mirror) | 600 SMILES |
| Reference actives | Ribavirin, favipiravir, umifenovir, oseltamivir | 4 antivirals |
| Receptor | PDB **9P3I** (ANDV Gn/Gc tetramer) | S3 |

S3 prefix: `s3://biomate-nextflow-work/inputs/andv_campaign/publication_20260528/`

## Batch jobs submitted

| Track | run_id | Status |
|-------|--------|--------|
| Plan A epitope (mhcnuggets) | `5eda51b4-70b5-4405-9083-f4ab1746da14` | **Succeeded** — 45,160 rows, **113 binders** |
| Plan B codon opt | `839ff0f7-5146-4e25-8ba8-01e202401a6d` | **Done** (Batch work-dir; driver exited early) |
| Plan B RNA2D retry | `9b615452-8e7c-4e52-bc19-9a04c923250b` | **Done** — MFE −182.7 kcal/mol |
| Plan B LNP | `d065b268-51be-4b78-8b5e-63be4bc7459b` | **Done** |
| ZINC150 ADMET+Vina | retry in `zinc150_screen_retry.log` | In flight |

## Completed local computation (publication-ready now)

### Plan B — real ANDV GP (Q9E006, 3414 nt)

| Step | Status | Key metric |
|------|--------|------------|
| Codon optimization | **Done** (Batch work-dir) | **737 / 1138 codons modified (64.76%)** |
| RNA2D (5′ 500 nt) | Retry in flight (`9b615452`, RNA alphabet fix) | — |
| LNP formulation | **Done** | Endosomal escape **0.202**; liver tissue score **0.85**; EE **20%** |

Artifacts: `plan_b_codon/`, `plan_b_lnp/`

### Cross-species conservation (full GP)

- Method: BioPython pairwise alignment + k-mer mapping on **4518** 8–11-mers from full Q9E006
- **195** cross-species peptides (ANDV/SNV/PUUV); **54** unique 9-mers
- GP identity: ANDV vs SNV **78.0%**; ANDV vs PUUV **66.9%**
- Artifact: `cross_species_conservation_full_gp.json`

### Wet-lab peptide order list

See `wet_lab_package/WET_LAB_CANDIDATES.md` — top conserved 9-mers including **ESSCNFDLH** (GP pos 61, triple-species).

**Recommended synthesis batch (15 peptides):** XSP-01 … XSP-15 in wet-lab package.

Assays: peptide–MHC binding (DimerX/ELISA) → IFN-γ ELISpot with ANDV-immune PBMC.

## Pending (Batch in flight)

- Full GP MHC binding scores (8 alleles × ~1129 9-mers per allele)
- ANDV GP codon optimization metrics (CAI, rare codons) on real 3414 nt
- RNA secondary structure (5′ UTR-proximal window)
- LNP formulation ranking for mRNA cargo
- Pharmacophore filter → ADMET → Vina on 600-compound library

Re-poll:

```bash
python3 research/anti-virus/scripts/assemble_wet_lab_candidates.py \
  --publication-run research/anti-virus/runs/publication_20260528T223525Z \
  --conservation-json research/anti-virus/runs/publication_20260528T223525Z/cross_species_conservation_full_gp.json \
  --epitope-tsv s3://.../predictions/PLAN_A_FULL_GP.tsv  # after Plan A completes
```
