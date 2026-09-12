# CZI training-donor attenuation diagnostic — 2026-09-12

Both panels show small mean MSE reductions after strong attenuation. These are exploratory known-target transfer diagnostics, not model promotion or independent biological validation. Both reuse the same four donors and controls; the basic-QC panel supplies different targets, not independent donors.

Aggregate effects use **all available NT controls** per donor/condition. Existing disjoint feature/reference pools are used only to fit attenuation. This differs from the reference-only labels used in the earlier donor-state model, so scores are not directly comparable. All 32 perturbed target genes across both panels are excluded from every arm and fit.

Each outer fold averages observed target effects over the other three donors. Per condition, attenuation fits a zero-intercept slope pooled across training guide pairs, symmetrizing guide order and disjoint-reference orientation, clipped to [0,1]. All/top128/top512 are fixed sensitivity settings; top panels use mean training-control CPM >=1 and variance across three-donor mean target effects, with stable gene-name ties. No settings were optimized.

| Dataset | Readouts | No change MSE | Shrunk matched MSE | Relative reduction | Donors improving | Alpha range |
|---|---|---:|---:|---:|---:|---:|
| selected | all | 0.00248573 | 0.00247986 | 0.236% | 4/4 | 0.00000–0.05530 |
| selected | 128 | 0.06054944 | 0.06007466 | 0.784% | 4/4 | 0.00000–0.14591 |
| selected | 512 | 0.02643732 | 0.02622220 | 0.814% | 4/4 | 0.00217–0.13031 |
| basic_qc | all | 0.00191392 | 0.00191106 | 0.149% | 4/4 | 0.00000–0.06101 |
| basic_qc | 128 | 0.05305035 | 0.05259841 | 0.852% | 4/4 | 0.01742–0.13376 |
| basic_qc | 512 | 0.02278868 | 0.02267080 | 0.517% | 4/4 | 0.00961–0.11685 |

Unattenuated matched effects remain worse than no change in every dataset/panel average. Small attenuation gains should be interpreted with donor-level variability, control reuse, shared-reference effects in aggregate labels, coverage selection, and development-stage inspection in mind. The coefficient is a predictive attenuation diagnostic, not an estimated causal effect or a biological noise ceiling.

`results.json` retains every coefficient, numerator, denominator, selected gene list, per-target metric, per-donor summary, and input/code hash. Correlation summaries contain valid and total counts: zero-alpha predictions have undefined correlation. Means conditional on valid correlations are not directly comparable when counts differ.

All **72 held-out mutation checks passed**: replacing every held-out aggregate effect, guide profile, control reference and control CPM with 1e9 left selection, attenuation coefficients and training target predictions exactly unchanged. This checks split isolation; it is not independent reconstruction of the full implementation.
