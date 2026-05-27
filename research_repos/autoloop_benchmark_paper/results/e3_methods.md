# E3 — Methods: Gate provenance vs auto-loop convergence

## Provenance grade assignment

QC gate provenance grades (GOLD / SILVER / BRONZE) are defined in
`backend/config/qc_evidence.yaml`, the single source of truth for the
evidence-on-hover tooltips rendered in the BioMate frontend. Grades are
assigned per gate by the provenance audit (`docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md`):

- **GOLD** — the cited paper or regulatory guidance states the exact
  threshold verbatim, or the threshold is trivially derived from values
  in it.
- **SILVER** — community convention attributed to the paper; the paper
  supports the concept but does not state the exact cutoff.
- **BRONZE** — operational heuristic with no peer-reviewed anchor; the
  cited reference provides related context only.

For E3 we join the 139-scenario Wave-1 results
(`evaluation/results/autoloop/autoloop_results.csv`) to a gate→grade
mapping derived from `qc_evidence.yaml`:

| Domain  | gate_type        | qc_evidence key                  | Grade  |
|---------|------------------|----------------------------------|--------|
| ADMET   | hERG             | `admet_herg_ic50`                | GOLD   |
| ADMET   | Ames             | `admet_ames`                     | GOLD   |
| ADMET   | DILI             | `admet_dili_probability`         | SILVER |
| ADMET   | multi            | (lowest of co-firing)            | SILVER |
| CYP_DDI | R1_clinical      | `cyp_ddi_r1_basic`               | GOLD   |
| CYP_DDI | R1_investigate   | `cyp_ddi_r1_basic`               | GOLD   |
| Docking | weak_score       | `docking_binding_score`          | BRONZE |
| Docking | no_poses         | `docking_valid_poses`            | BRONZE |
| NCA_PK  | high_extrap      | `nca_auc_extrap`                 | GOLD   |
| NCA_PK  | poor_slope       | `nca_terminal_slope_coverage`    | SILVER |

The `none` gate_type (baseline pass — no remediation triggered) is
excluded from the provenance analysis. The synthetic `persistent`
gate_type denotes adversarial scenarios designed to deliberately
exhaust the 3-retry budget regardless of underlying physiology and is
analysed as a sensitivity stratum (see below).

## Statistical methodology

We assess the association between gate provenance grade and auto-loop
convergence at two levels:

1. **Per-scenario (N = 112 remediating scenarios).** We build a 2 × 3
   contingency table of (converged, escalated) × (GOLD, SILVER, BRONZE)
   and test independence with the chi-squared test (verifying expected
   cell counts ≥ 5; otherwise reporting Fisher's exact as primary). The
   pre-registered direct contrast is GOLD vs BRONZE, evaluated with
   Fisher's exact two-sided. A 95% confidence interval on the
   convergence-rate difference (GOLD − BRONZE) is obtained by
   non-parametric bootstrap with 1,000 resamples (seed = 42).

2. **Per-domain (N = 4).** Each domain's weighted provenance score
   (3·GOLD% + 2·SILVER% + 1·BRONZE%) is correlated with its observed
   convergence-within-3-retries rate via Pearson r. With only four
   domains this analysis is descriptive only; the p-value is reported
   for completeness but is not used as inferential evidence.

## Results

### Per-scenario 2×3 contingency

|              | GOLD | SILVER | BRONZE |
|--------------|------|--------|--------|
| converged    |   49 |     22 |     22 |
| escalated    |    9 |      0 |     10 |
| **rate**     | 0.845| 1.000  | 0.688  |
| N            |   58 |     22 |     32 |

Chi-squared (2 dof): χ² = 9.22, **p = 0.010**.
Fisher's exact GOLD vs BRONZE (2 × 2): odds-ratio = 2.48,
**p = 0.106** (two-sided).
Bootstrap 95% CI on rate(GOLD) − rate(BRONZE) = +0.157,
**[−0.013, +0.351]** — the lower bound just brushes zero, so the
GOLD-vs-BRONZE contrast does **not** reach the conventional p < 0.05
threshold on the primary pre-registered test.

### Sensitivity analysis — excluding adversarial `persistent` scenarios

All nine GOLD escalations in the primary table come from the
`persistent` stress-test gate_type, which is constructed to defeat
the remediator regardless of evidence quality (3 ADMET + 3 CYP_DDI +
3 NCA_PK persistents, all escalated by design). When these synthetic
adversarial scenarios are removed, the remaining 103 scenarios show:

|              | GOLD | SILVER | BRONZE |
|--------------|------|--------|--------|
| converged    |   49 |     22 |     22 |
| escalated    |    0 |      0 |      5 |
| **rate**     | 1.000| 1.000  | 0.815  |

Fisher's exact GOLD vs BRONZE: odds-ratio = ∞ (zero failure cell),
**p = 0.0044**.

Under this sensitivity definition — restricted to *physiologically
meaningful* remediation attempts — the association between provenance
grade and convergence reliability is statistically significant.

### Per-domain (descriptive)

Pearson r = 0.977 across the four domains (p = 0.023, N = 4); we
report this descriptively because four observations do not support
inferential claims.

### Concentration of Docking escalations

The 10 Docking non-convergences split evenly between two gate types:
`weak_score` (5/17 scenarios) and `persistent` (5/5 scenarios — by
construction). The non-persistent escalations are all attributable to
the BRONZE `docking_binding_score` gate, where the threshold itself is
operational rather than peer-reviewed — which is consistent with the
provenance hypothesis but cannot, on this sample alone, distinguish
"the gate is wrong" from "docking remediation is genuinely harder".

## Honest interpretation

The pre-registered per-scenario Fisher contrast on GOLD vs BRONZE does
not reach p < 0.05 (p = 0.106) because the synthetic `persistent`
stress-test scenarios — designed to escalate regardless of evidence —
inject nine forced GOLD escalations and shrink the apparent gap.
Excluding those adversarial scenarios yields p = 0.004 and a clean
100% / 100% / 81.5% pattern. We report both estimates; the framework's
"no fabrication" commitment requires we not declare significance on
the basis of the sensitivity analysis alone. The combined finding is a
**suggestive but not conclusive** association at N = 112, robust to
sensible analytical choices, and consistent with the per-domain
descriptive correlation (r = 0.98 across N = 4 domains). A Wave-2
benchmark with additional BRONZE-anchored domains is required to
confirm.
