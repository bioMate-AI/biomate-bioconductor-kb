# Plan A — population coverage (compute-only)

Generated: 2026-06-03T16:43:00.406052+00:00

**Primary population:** Chile (see `docs/PLAN_A_POPULATION_SURVEY.md`)

_In silico estimate only. Validates HLA genetics + predicted binding; not immunogenicity._

## Coverage by epitope subset

### all_consensus_pairs (247 pairs)

| Population | Coverage % | HLA-A % | HLA-B % |
| --- | ---: | ---: | ---: |
| Chile | **77.89** | 48.3 | 57.23 |
| Argentina | **67.26** | 41.17 | 44.35 |
| Peru | **66.56** | 37.59 | 46.42 |
| World | **72.68** | 48.16 | 47.29 |

### tier_A_surface_conserved (5 pairs)

| Population | Coverage % | HLA-A % | HLA-B % |
| --- | ---: | ---: | ---: |
| Chile | **17.74** | 0.0 | 17.74 |
| Argentina | **8.8** | 0.0 | 8.8 |
| Peru | **19.54** | 0.0 | 19.54 |
| World | **11.26** | 0.0 | 11.26 |

### tier_A_B_surface (30 pairs)

| Population | Coverage % | HLA-A % | HLA-B % |
| --- | ---: | ---: | ---: |
| Chile | **48.81** | 25.87 | 30.94 |
| Argentina | **38.53** | 19.9 | 23.26 |
| Peru | **44.16** | 17.55 | 32.27 |
| World | **42.62** | 21.15 | 27.24 |

### tier_C_cytoplasmic_excluded_from_design (20 pairs)

| Population | Coverage % | HLA-A % | HLA-B % |
| --- | ---: | ---: | ---: |
| Chile | **47.81** | 26.38 | 29.1 |
| Argentina | **41.65** | 23.96 | 23.26 |
| Peru | **39.07** | 22.21 | 21.68 |
| World | **55.92** | 30.78 | 36.32 |

## Greedy optimized set (Chile)

Baseline (all tier A+B pairs): **48.81%**

| Rank | Peptide | Coverage % | Marginal gain (pp) |
| ---: | --- | ---: | ---: |
| 1 | KTFEGILTK | 25.87 | 25.87 |
| 2 | MPDVAHSL | 39.02 | 13.15 |
| 3 | MPKTIYELKM | 45.81 | 6.79 |
| 4 | SRMLVHPR | 48.81 | 3.0 |
| 5 | NPAHTLTL | 48.81 | 0.0 |

Full table: `PLAN_A_CHILE_OPTIMIZED_EPITOPE_SET.tsv`

Cross-check: upload `PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv` to [IEDB Population Coverage](https://tools.iedb.org/population/).
