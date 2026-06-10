# QC Evidence Provenance Audit — Pass 3 (2026-06-10)

**Scope:** Re-audit of the **22 remaining GOLD entries** in
`backend/config/qc_evidence.yaml` after pass 2 (`docs/20260607_QC_EVIDENCE_AUDIT_PASS_2.md`)
demoted 4 of the original 26.

**Outcome:** Zero new full demotions. Three entries flagged for
**inline split-tier honesty notes** — the primary cutoff IS GOLD, but a
secondary tier in the same rule is BioMate operational. Updated
`rule_text` to call that out explicitly.

## Spot-checks that PASSED audit (legitimate GOLD)

These were each verified against the cited paper's specific numeric
claim:

| Entry | Cited paper | Numeric anchor |
|---|---|---|
| `hts_z_prime` | Zhang 1999 | ≥ 0.5 "excellent" verbatim |
| `hts_signal_window` (ICH S7B) | ICH S7B guidance | <10× / <30× verbatim |
| `hts_signal_window` (Dutta 2017) | Dutta 2017 | qNET < -30 pC/pF verbatim |
| `struct_pred_mean_plddt` | Jumper 2021 AlphaFold | pLDDT 70-90 band stated |
| `boin_dlt_boundary` | Liu & Yuan 2015 | λ_e, λ_d Table 2 verbatim |
| `cyp_ddi` R1 | FDA 2020 DDI | 1.02 / 1.1 cutoffs verbatim |
| `cyp_ddi` R2 | FDA 2020 DDI | 0.79 / 0.71 cutoffs verbatim |
| `ivive_fold_error` | Obach 1999 | 2-fold criterion stated |
| `openfe_cycle_closure` | Mey 2020 | <1 kcal/mol stated |
| `p0_pkpd_weight_loss_band` | Overgaard 2019 | ±3 to -6 kg band stated |
| `pocket_druggability_score` | Le Guilloux 2009 | ≥ 0.5 druggable stated |
| `cancer_somatic_vaf_min` | GATK Best Practices | VAF ≥ 0.05 stated |
| `cancer_somatic_depth_min` | Strelka2 paper Table 2 | 30× stated |
| `ab_tap_cdr_length` | Raybould 2019 Table 1 | 43-63 residues CST 5th-95th stated |
| `ab_tap_surface_hydrophobicity` | Raybould 2019 Table 1 | 90-150 PSH band stated |
| `sirna_thermodynamic_asymmetry` | Khvorova 2003 | ΔdG ≥ 0.5 kcal/mol stated |
| `nlmixr2_eta_shrinkage` | Savic & Karlsson 2007 | 20% / 30% cutoffs stated |
| `pbpk_mass_balance` | EMA PBPK 2019 | Mass balance principle stated |
| `pbpk_auc_fold_error` | FDA 2018 PBPK | 2-fold verbatim |
| `admet_pbpk_auc_fold_error` (Redfern hERG) | Redfern 2003 | 30× margin → 10 µM IC50 verbatim |
| `admet_ames` (Lipinski Ro5) | Lipinski 1997 | 4 cutoffs + "2+ violations" verbatim |
| `nca_auc_extrap` | FDA 2003 BA/BE | 20% verbatim |

## Inline split-tier honesty notes added (this pass)

Three entries had a GOLD-anchored primary cutoff plus a BioMate-operational
secondary tier in the same `rule_text`. The combined rule was correctly
labelled GOLD but the operational tier wasn't called out. Updated to
the split-grade template (mirroring `allometric_r_squared` and the
cryo-EM resolution tier pattern from pass 2):

### 1. `pbpk.pbpk_auc_fold_error`
- Before: "IND profile, 2-fold OR screening, 3-fold"
- After: same, plus "The 2-fold IND tier is GOLD-anchored to FDA 2018
  verbatim; the 3-fold screening tier is BioMate-operational (a
  relaxed pre-IND filter, not in the guidance)."

### 2. `nca_pk.nca_auc_extrap`
- Before: "halts when AUC_extrap_pct > 20% (nca_standard); regulatory
  profile tightens to > 15%."
- After: same, plus "The 20% cutoff is GOLD-anchored to FDA 2003
  verbatim; the 15% regulatory tier is BioMate-operational (a stricter
  pre-NDA filter, not in the guidance)."

### 3. `ich_s5.ich_s5_safety_margin`
- Before: "flags compounds with safety margin < 10× Cmax under the
  WOCBP scenario (RED) or 10-30× (YELLOW)"
- After: same, plus "The < 10× RED tier is GOLD-anchored to ICH S5(R3)
  §3.1 verbatim; the 10-30× YELLOW intermediate band is
  BioMate-operational (early-warning tier, not in the guidance)."

## Why not a full demotion?

Each of those three rules HAS a GOLD-anchored primary cutoff. Demoting
the whole entry to SILVER would understate the strength of the regulatory
tier. The split-grade inline note is the honest middle: it preserves
the GOLD on the part that is GOLD, and names which tier is operational.

This is the same pattern pass 2 established and the audit doc described
as "the template for any new entry."

## Counts after pass 3

| Grade | Pre-pass-2 | Post-pass-2 | Post-pass-3 |
|---|---|---|---|
| GOLD | 26 | 22 | 22 |
| SILVER | 26 | 30 | 30 |
| BRONZE | 5 | 5 | 5 |
| **Total** | 57 | 57 | 57 |

GOLD count unchanged because no full demotions. SILVER unchanged because
the 3 inline notes don't change the entry's provenance tag — they make
the `rule_text` more honest about which side of the rule is regulatory.

## What this means for product / regulatory

When a CRO QA pack quotes a GOLD-tier gate, the cited paper now states
*both* tiers of the BioMate rule, OR the YAML now says explicitly that
the auxiliary tier is operational. Reviewers can no longer be confused
about which cutoff has regulatory backing.

## Files touched

- `backend/config/qc_evidence.yaml` — three `rule_text` clarifications

## Related

- `docs/20260607_QC_EVIDENCE_AUDIT_PASS_2.md` — pass 2 (the 4 demotions)
- `docs/20260609_QC_COVERAGE_EXPANSION.md` — technical companion
- `docs/20260610_QC_COVERAGE_TEAM_BRIEF.md` — non-technical reader brief
