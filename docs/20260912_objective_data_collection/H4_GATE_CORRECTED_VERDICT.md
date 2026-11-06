# H4 leave-HLA-out gate — CORRECTED verdict (supersedes LEAVE_HLA_OUT_RESULT.json)

Date 2026-09-13. After a 3-way adversarial double-check (A375 diagnostic, independent
gate recompute, exhaustive data rescan). The original `LEAVE_HLA_OUT_RESULT.json` FAIL
("public data actively contradicts H4 transfer") is **UNSAFE and superseded** — it was
driven by two artifacts, not biology.

## What was wrong with the original FAIL (ρ=−0.93)
1. **Gene mislabel (sign-inverting):** HeLa's KO is **TAPBPR** (editor, TAPBPL, weak) but was
   labeled **TAPBP** (hard-essential, severity 0.80) in `build_inventory.py`. Correcting it
   flips the HAP1 fold ρ from −0.92 → **+0.92**. The negative headline was this bug.
2. **Prep-method confound (false contradiction):** A375 B2M-KO "88% retained" is a
   **mild-acid-elution** artifact (co-elutes B2M-independent intracellular background). On
   genuine-HLA-ligand scoring, A375 B2M-KO retention = **0.119**, collapsing like HAP1 (0.028).
   KO is clean (B2M peptides → 0 in KO); the retained peptides are mostly non-ligands.
3. **Disjoint-allele check non-functional** (parser split on `,`, data uses `;`) — always
   returned "disjoint." Biologically the public hard-essential backgrounds are all HLA-A\*02.

## Corrected verdict: UNPROVEN (underpowered) — NOT contradicted, leaning positive
- Every clean hard-essential B2M-KO background, measured on genuine ligands, **collapses**
  (HAP1 0.028, A375 0.119) → **consistent** cross-background support for the H4 thesis.
- It still cannot PASS, for a REAL (non-bug) reason: only ~1 informative fold, and **all
  public hard-essential KO data is HLA-A\*02** — there is no disjoint-allele test to run.

## Data rescan: CONFIRMED no missed public data
Exhaustive PRIDE/MassIVE/ProteomeXchange/GEO/literature search → **0** fetchable
hard-essential-KO immunopeptidomes on a disjoint (non-A\*02) allele.
- New find **PXD063813** (B2M-KO in C1R-A\*02 & K562-A\*02): still A\*02, and its held file is
  tryptic whole-**proteome** (not ligandome) — needs no-enzyme reprocessing of raw `.d`.
- MSV000091285 = drug (proteasome inhibitor), not genetic KO. Non-qualifying.

## Net conclusion
- The **CRO is still required** — but for a precisely defined and NARROWER reason: public
  data establishes the mechanism on the A\*02 axis; it structurally cannot test **disjoint-allele
  generalization**. The CRO must supply hard-essential KO (B2M/TAP1/TAP2/TAPBP) on **≥3
  disjoint-allele backgrounds** with a **consistent antibody-IP method + matched proteome +
  verified-complete KO + absolute quant**.
- Risk is LOWER than the original FAIL implied: the thesis is consistent everywhere it is
  cleanly measured; the gap is coverage, not contradiction.

## Cheap compute-only steps before committing CRO spend
1. **Re-run the corrected gate**: fix the TAPBPR severity + disjoint-allele parser, and
   re-score ALL deposits on genuine-HLA-ligand retention (so acid-elution vs IP are comparable).
   Yields the authoritative UNPROVEN number.
2. **Reprocess PXD063813 no-enzyme** (C1R/K562 HLA-null single-A\*02 parents): a clean B2M-KO
   ligandome collapse there confirms the mechanism on defined single-allele lines and localizes
   any residual A375 oddity to A375, not A\*02 biology. Zero acquisition cost.

## ADDENDUM (post-renormalization) — HAP1 genotype correction
Corpus renormalization resolved **HAP1 = A\*02:01/B\*40:01/C\*03:04** (expression-validated),
NOT the A\*03:01/B\*51:01/C\*01:02 the corrected-gate agent used. Consequences:
- The gate's "HAP1 is allele-disjoint" claim is WRONG. **All four public hard-essential
  backgrounds (HAP1, A375, THP-1, HeLa) are HLA-A\*02:01** → ZERO allele-disjoint backgrounds.
- The +0.68 transfer is therefore "machinery→presentation transfers across A\*02 CELL LINES"
  (real, encouraging — not HAP1-specific), but **cross-ALLELE generalization is entirely
  untested** on public data. This makes the disjoint-allele CRO requirement absolute, not
  marginal: no non-A\*02 hard-essential-KO ligandome exists anywhere public.
- Verdict unchanged (UNPROVEN across HLA); the *reason* is now cleaner: not "1 disjoint fold",
  but "all evidence is single-allele A\*02".
- The wrong genotype had depressed HAP1's ligand-fraction ~20× (0.04→0.79) — a reminder to
  score each deposit against its OWN validated alleles.

training_eligible=false throughout.
