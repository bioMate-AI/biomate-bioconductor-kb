# Plan B remaining — consolidated 2026-06-03

All Plan B compute steps for publication run `20260528T223525Z` are **complete**.

| Step | Artifact | Status |
|------|----------|--------|
| Codon optimization | `plan_b_codon/` | Done — 737/1138 codons (64.76%) |
| RNA2D 5′ window | `plan_b_rna2d/` | Done — MFE −182.7 kcal/mol |
| LNP formulation | `plan_b_lnp/lnp_results.json` | Done — pKa SUBOPTIMAL |
| ANDV P0 QC | `plan_b_p0/andv_p0_mrna_validation_report.json` | PASS |
| Spike 12819 P0 | `plan_b_p0/spike_12819/` | PASS |
| NP-PK | `plan_b_np_pk/np_pk_results.json` | Done — stealth POOR |

**Wet-lab synthesis spec:** `plan_b_wet_lab/PLAN_B_WET_LAB_SPEC.md`

**Open items:** LNP reformulation (pKa); pull optimized CDS from S3; manuscript v1.1 polish.

See [`docs/20260603_ANDV_THREE_TRACKS_STATUS_AND_PLAN.md`](../../../docs/20260603_ANDV_THREE_TRACKS_STATUS_AND_PLAN.md).
