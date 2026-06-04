# Plan A — population coverage (compute-only)

Generated: 2026-06-03T06:01:10.290286+00:00

**Primary population:** Chile (see `docs/PLAN_A_POPULATION_SURVEY.md`)

_In silico estimate only. Validates HLA genetics + predicted binding; not immunogenicity._

## Coverage by epitope subset

### all_consensus_pairs (47 pairs)

| Population | Coverage % | HLA-A % | HLA-B % |
| --- | ---: | ---: | ---: |
| Chile | **54.66** | 42.24 | 21.5 |
| Argentina | **54.86** | 41.17 | 23.26 |
| Peru | **51.12** | 37.59 | 21.68 |
| World | **62.28** | 48.16 | 27.24 |

### tier_A_surface_conserved (4 pairs)

| Population | Coverage % | HLA-A % | HLA-B % |
| --- | ---: | ---: | ---: |
| Chile | **7.46** | 0.0 | 7.46 |
| Argentina | **8.8** | 0.0 | 8.8 |
| Peru | **8.03** | 0.0 | 8.03 |
| World | **11.26** | 0.0 | 11.26 |

### tier_A_B_surface (28 pairs)

| Population | Coverage % | HLA-A % | HLA-B % |
| --- | ---: | ---: | ---: |
| Chile | **36.13** | 18.64 | 21.5 |
| Argentina | **38.53** | 19.9 | 23.26 |
| Peru | **35.43** | 17.55 | 21.68 |
| World | **42.62** | 21.15 | 27.24 |

### tier_C_cytoplasmic_excluded_from_design (19 pairs)

| Population | Coverage % | HLA-A % | HLA-B % |
| --- | ---: | ---: | ---: |
| Chile | **42.21** | 26.38 | 21.5 |
| Argentina | **41.65** | 23.96 | 23.26 |
| Peru | **39.07** | 22.21 | 21.68 |
| World | **49.63** | 30.78 | 27.24 |

## Greedy optimized set (Chile)

Baseline (all tier A+B pairs): **36.13%**

| Rank | Peptide | Coverage % | Marginal gain (pp) |
| ---: | --- | ---: | ---: |
| 1 | KTFEGILTK | 18.64 | 18.64 |
| 2 | ESKFKFIL | 26.88 | 8.24 |
| 3 | MPDVAHSL | 32.63 | 5.74 |
| 4 | QRFRGSEQKINF | 36.13 | 3.51 |
| 5 | QRFRGSEQKI | 36.13 | 0.0 |

Full table: `PLAN_A_OPTIMIZED_EPITOPE_SET.tsv`

Cross-check: upload `PLAN_A_POP_COVERAGE_INPUT.tsv` to [IEDB Population Coverage](https://tools.iedb.org/population/).
