# QC Evidence Provenance Audit — Pass 2 (2026-06-07)

**Scope:** Re-audit of GOLD-graded entries in `backend/config/qc_evidence.yaml`,
asking: does the cited paper actually state the numeric cutoff that BioMate
uses, or only the metric / methodology?

**Outcome:** 4 of 26 GOLD entries demoted to SILVER (~15% overgrade rate).

## Demotions

### 1. `admet.admet_ames` (Kazius 2005) → SILVER
- Paper: Kazius J et al. *J Med Chem* 2005; 48:312-320
- Cutoff: Ames probability > 0.5
- **Why demoted:** Kazius 2005 defines the structural-alert SET, not a
  classifier probability cutoff. The 0.5 cutoff is the generic
  binary-classifier midpoint, not Kazius-derived.

### 2. `allometric.allometric_r_squared` (FDA 2005 FIH) → SILVER
- Paper: FDA *Estimating the Maximum Safe Starting Dose in Initial Clinical Trials* (2005)
- Cutoff: R² < 0.85
- **Why demoted:** The guidance describes allometric scaling and notes
  fit quality as a critical input but does NOT state R² ≥ 0.85 as a
  specific cutoff. The 0.85 value is community convention from
  pharmacokinetic textbooks (Mahmood 2007; Tang & Mayersohn 2005),
  not regulatory guidance.

### 3. `cryo_em.cryo_em_fsc_resolution` (Rosenthal & Henderson 2003) → SILVER
- Paper: Rosenthal PB & Henderson R. *J Mol Biol* 2003; 333:721-745
- Cutoff: FSC 0.143 > 4 Å (publication), 8 Å (advisory), 15 Å (FAIL)
- **Why demoted:** R&H 2003 establish the FSC 0.143 METRIC. The paper
  does NOT state specific resolution-value cutoffs. The 4/8/15 Å
  tiers are BioMate operational tiers reflecting today's publication
  norms.

### 4. `cryo_et.cryo_et_sta_fsc_resolution` (Rosenthal & Henderson 2003) → SILVER
- Same paper as above
- Cutoff: STA FSC 0.143 > 15 Å (advisory), > 30 Å (FAIL)
- **Why demoted:** Same root cause — the METRIC is GOLD, the BioMate
  resolution-value tiers are operational.

## Pattern

A GOLD grade requires the paper to state the numeric value verbatim or
trivially derive it from values in the paper. "The paper establishes the
metric" is not sufficient — when the cutoff is a community convention
or BioMate operational choice, the entry is at most SILVER.

The split-grade pattern used in the corrected entries is the right
template: "metric X is GOLD-anchored to paper Y; the specific cutoff
value is operational (SILVER)."

## Counts after Pass 2

| Grade | Before | After |
|-------|--------|-------|
| GOLD | 26 | 22 |
| SILVER | 26 | 30 |
| BRONZE | 5 | 5 |
| **Total** | 57 | 57 |

## Still-uninspected

The 26 GOLD entries before this pass include the 22 retained; spot-checks
confirmed legitimate GOLD on: Zhang 1999 (Z'≥0.5 verbatim), ICH S5R3 §3.1
(≥10× margin verbatim), Redfern 2003 (30× hERG margin verbatim), Obach
1999 (2-fold IVIVE verbatim), Mey 2020 (cycle-closure < 1 kcal/mol
verbatim), Le Guilloux 2009 (druggability ≥ 0.5 verbatim), Liu & Yuan 2015
(BOIN λ values verbatim), Lipinski 1997 (Ro5 verbatim), FDA 2003 BA/BE
(20% AUC extrap verbatim), Raybould 2019 (CDR/PSH percentile bounds
verbatim), Khvorova 2003 (ΔdG 0.5 kcal/mol verbatim).

## Related

- `docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md` — earlier pass
  that established the GOLD/SILVER/BRONZE framework
