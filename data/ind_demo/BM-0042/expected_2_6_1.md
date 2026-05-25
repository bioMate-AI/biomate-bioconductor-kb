# Expected §2.6 Output for BM-0042

This is the prose the BioMate regulatory LLM (v6 public adapter) should produce given the inputs in this directory. It's used as the **gold standard** to compare against during demo dry-runs and to score the LLM when this dataset is added to the eval suite.

---

## §2.6.1 — Pharmacology Written Summary

**[BioMate-generated draft]** BM-0042 is a covalent third-generation EGFR tyrosine kinase inhibitor selective for the EGFR L858R/T790M double-mutant kinase domain, intended for second-line treatment of non-small cell lung cancer following failure of first- or second-generation EGFR TKIs. The compound was selected from a 12-member library following BioMate's two-round auto-loop ADMET screen, which excluded four compounds for hERG, DILI, or Ames liabilities and one for Lipinski rule-of-five non-compliance (MW > 500 Da).

BM-0042-001 demonstrated potent EGFR L858R/T790M inhibition with a >50-fold selectivity window over wild-type EGFR. In a 28-day GLP repeat-dose rat study, the no-observed-adverse-effect level (NOAEL) was established at 15 mg/kg/day on the basis of hepatocellular hypertrophy and single-cell necrosis observed at the 50 mg/kg/day high dose. Application of FDA 2005 MRSD guidance — animal-to-human conversion factor of 6.2 and a safety factor of 10 — yields a maximum recommended starting dose of 0.24 mg/kg, or approximately 14.5 mg in a 60-kg adult human; the planned Phase 1 starting dose has been conservatively set at 10 mg.

## §2.6.2 — Pharmacology Tabulated Summary

Reference set qualification of the BioMate-built PK-Sim PBPK platform was performed against 18 marketed compounds spanning the OSP-curated reference set (Edginton 2008). The platform achieved Cmax within-2-fold of observed values in 16 of 18 cases (89%), exceeding the EMA 2018 PBPK qualification threshold of ≥80%. AUC within-2-fold was 83% (15 of 18). These results fall within the OSP-approved range of 75-95% for EMA-accepted PBPK platforms.

## §2.6.3 — Pharmacokinetics Written Summary

BM-0042-001 exhibits high oral bioavailability (F = 71% in rat) with low to moderate hepatic clearance (CLint = 12.4 µL/min/mg in pooled human liver microsomes; predicted human CL = 8.9 L/h). Plasma protein binding is high (98.1%) with fraction unbound f_u = 0.019. Volume of distribution is moderate (Vd = 1.6 L/kg), and predicted human terminal half-life is 14.2 h, supporting once-daily dosing.

## §2.6.5 — Toxicology Written Summary

In the pivotal 28-day GLP repeat-dose rat toxicology study (T-28R-0042), BM-0042-001 was administered by oral gavage at 5, 15, and 50 mg/kg/day to groups of 10 Sprague-Dawley rats per sex per dose. One high-dose male was euthanized moribund on day 23 with marked hepatocellular necrosis at necropsy. Body-weight gain was reduced at the high dose (-3.2% vs. +12.4% in controls). Mild hepatocellular hypertrophy was observed at mid and high doses; single-cell necrosis was confined to the high dose. Minimal tubular regeneration in the kidney was noted in 3 of 10 high-dose males. No findings of regulatory concern were observed at 15 mg/kg/day; this dose was therefore designated the NOAEL.

Safety pharmacology assessments per ICH S7A/S7B revealed a transient ~18% increase in heart rate at the 50 mg/kg dose in conscious telemetered dogs, with no QTc prolongation at any dose. Cellular hERG IC50 was 18.4 µM, providing a >20-fold margin over unbound human Cmax projected at the MRSD. The compound was non-genotoxic across the standard ICH S2(R1) battery (Ames, in vitro micronucleus, in vivo comet).

---

## Checker findings the LLM should ground inline

| Checker | Where chip should appear | Severity | Why |
|---|---|---|---|
| `MRSD_PRESENT` | §2.6.1 paragraph 2 | INFO | MRSD calc is fully shown and traceable to FDA 2005 |
| `PHASE_GATING` | §2.6.2 paragraph 1 | INFO | PBPK qualification cites the EMA 2018 threshold |
| `TABULATED_VS_PROSE` | §2.6.2 | INFO | Numbers in prose match tabulated values |
| `ADVERSITY_TENSE` | §2.6.5 paragraph 1 | INFO | Adverse findings stated in past tense, attributed to dose group |
| `STRUCTURED_TOX_ATTRIBUTION` | §2.6.5 | INFO | Target organs + NOAEL rationale present |

Zero findings at ⚠ MAJOR or above. If the LLM produces output that fails any of the above checkers, that's a regression — capture as a benchmark case in `evaluation/datasets/regulatory_llm_eval/`.
