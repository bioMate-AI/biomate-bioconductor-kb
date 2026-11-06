# Virtual Biotech claim: does target cell-type specificity predict clinical progression? (BioMate-data replication test)

Date: 2026-11-01. Script: `evaluation/virtual_biotech/switchlike_prior_test.py`; result: `evaluation/virtual_biotech/switchlike_result.json`
(per-drug table in S3). Run on a spot EC2 instance (r6i.xlarge), not the laptop.

## What was tested
Zhang & Zou (Science 2026) report that drugs aimed at switch-like, cell-type-specific genes were about 40% more likely to advance
Phase 1 to 2, about 48% more likely to reach market, with fewer adverse events. We tested the direction on public data:
- Trials: full ClinicalTrials.gov registry (609,551 studies, data timestamp 2026-10-30), mirrored to S3 on 2026-11-01.
- Drug to target: Open Targets 26.09 (drug names and synonyms, single-protein mechanism of action).
- Specificity: Human Protein Atlas single-cell RNA, tau index across cell types (genes with max nCPM >= 1).
- Unit: drug with a Phase 1 trial starting by 2016-12-31 (at least 10 years of follow-up), with a single-protein target and an HPA value.
- Pre-specified before running: high = top quartile of tau (cutoff 0.989); outcomes = a Phase 2+ trial, a Phase 3+ trial, approved;
  risk ratio with 95% CI from bootstrapping targets, adjusted logistic regression (drug type, start year, number of Phase 1 trials),
  and a shuffled-tau control. Phase 1/2 trials count as Phase 1.

## Result (1,884 drugs, 595 targets; 41.2% of drug and biologic interventions matched a drug name)
| Outcome | Rate, low specificity | Rate, high | Risk ratio (95% CI) | Shuffled-control p | Adjusted OR (95% CI) |
|---|---|---|---|---|---|
| Phase 2+ trial | 0.848 | 0.909 | 1.07 (1.03-1.12) | 0.008 | 1.89 (1.20-2.98) |
| Phase 3+ trial | 0.553 | 0.652 | 1.18 (1.05-1.33) | 0.016 | 1.60 (1.15-2.24) |
| Approved | 0.430 | 0.504 | 1.17 (0.98-1.37) | 0.059 | 1.44 (1.00-2.07) |

Secondary, uncorrected, no interval: the "enriched" flag gave risk ratios 1.28, 1.79 and 2.19 for the three outcomes.

## Reading
- The direction agrees with the paper for all three outcomes. Phase 2+ and Phase 3+ exclude 1 and beat the shuffled control; approval is borderline.
- The effect is smaller than the paper's headline numbers (+40%, +48%). Do not say it reproduces them.
- Base rates are very high (85% reach Phase 2), so the ratio is capped. Open Targets contains mainly drugs curated by ChEMBL, which
  under-represents early failures. This survivorship bias compresses risk ratios and may distort the adjusted odds ratios.
- The adjusted logistic models printed convergence warnings; treat the odds ratios as indicative only.
- Correlational. Disease area and modality beyond drug type are not controlled. HPA single-cell types are healthy cell types, a proxy for
  the paper's atlases. Exact-name matching dropped 59% of interventions (many are placebo or non-drug arms).
- This tests the prior only. It does not test the agent system, and it is not a validated target-triage tool.

## Next
Use a cleaner denominator (all registered drugs, not just curated ones), add disease-area stratification, and swap in CELLxGENE or
Tabula Sapiens; then, if the prior holds, add it as a labelled feature in the target-ID engine.
