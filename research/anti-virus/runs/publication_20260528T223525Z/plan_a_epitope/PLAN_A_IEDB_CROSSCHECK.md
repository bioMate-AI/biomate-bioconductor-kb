# Plan A — IEDB population coverage cross-check

Generated: 2026-06-04T16:17:30.322708+00:00

## Local recomputation (Bui et al. / IEDB method)

| Field | Value |
| --- | --- |
| Input TSV | `PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv` |
| Epitope–allele pairs | **30** |
| Unique peptides | 28 |
| Chile coverage (recomputed) | **48.81%** |
| Expected (tier A+B, 17-allele dual) | **48.81%** |
| Reference JSON (`tier_A_B_surface`) | 48.81% |
| Δ vs expected | +0.00 pp |
| Internal consistency | **PASS** |

## Manual IEDB web cross-check

1. Open [IEDB Population Coverage](https://tools.iedb.org/population/).
2. Upload `PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv` (peptide + HLA alleles).
3. Select population **Chile** (or match AFND frequencies used in `hla_frequencies_iedb_merged.tsv`).
4. Compare reported population coverage to **48.81%** (±1 pp tolerance).

Record the IEDB-reported percentage in the table below when available:

| Source | Chile tier A+B % | Notes |
| --- | ---: | --- |
| BioMate local (this script) | **48.81** | From upload TSV + AFND freq table |
| `PLAN_A_CHILE_POPULATION_COVERAGE.json` | 48.81 | Subset `tier_A_B_surface` |
| IEDB web tool | _pending manual run_ | Paste result after upload |

## Interpretation

Local recomputation validates that the **48.81%** claim is consistent with the IEDB upload file and frequency table. A separate web-tool run is still recommended for external audit; allele naming and population labels must match IEDB defaults.
