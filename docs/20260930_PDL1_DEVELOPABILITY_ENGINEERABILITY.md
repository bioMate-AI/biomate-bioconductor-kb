# PD-L1 Round-1 — Developability Engineerability + N-methylation Pass

**Date:** 2026-09-30 · **Context:** ACT cyclic-peptide program. Answers the review question
"developability should factor into candidate selection — does *none* of the 199 make it?"
Companion to `20260930_CYCLIC_PEPTIDE_END_TO_END_PROCESS.md` and the clinical-PK anchors
(`20260930_CLINICAL_PDL1_MACROCYCLE_PK_ANCHORS.md`).

## The question, answered honestly
- Against the **naive 2D oral window** (TPSA ≤ 180, HBD ≤ 6): **0 / 176 designable designs pass** — and
  even full N-methylation only removes ~110 Å² of 2D TPSA (median 487 → ~373), so nothing clears 180.
- **But 2D TPSA is the wrong ruler for chameleonic macrocycles.** Cyclosporine (oral, MW 1202, cyclic
  11-mer) has 2D TPSA ~279 (> 180) yet is orally bioavailable — its **3D**-PSA collapses via transannular
  H-bonds once N-methylated. Gating on 2D TPSA would wrongly discard the entire pool.

## The defensible discriminator: H-bond DONOR floor
Lokey's work establishes **HBD count as the #1 validated passive-permeability driver** for macrocycles.
We split each design's HBD into:
- **backbone-amide HBD** — REMOVABLE by N-methylation (the cyclosporine lever), and
- **side-chain HBD** — a **FIXED floor** only sequence redesign can change.

A design is **engineerable to the oral window** iff its side-chain HBD floor ≤ 6 AND HBD ≤ 6 is reachable
within its backbone-amide count.

## Result
- **118 / 176 designs are HBD-engineerable.** Side-chain floor across the pool: min 1, median 5.5, max 15.
- Each engineerable design has a concrete N-methyl projection (k = HBD − 6 backbone amides; feasibility
  reference: cyclosporine = 7 N-Me on an 11-mer).
- **Honest binding trade-off:** the strongest raw binders (d0/d1, iptm 0.55–0.61) are **polar** (high
  side-chain floor) → **not** engineerable; the best engineerable binders reach iptm ~0.52–0.55 (PD-L1 flat
  interface ceiling 0.626). Trading a little binding for developability-viability is the correct call for an
  oral asset.

## So the round-1 selection logic (matches how the field selects)
Binders first (binding × designability × diversity) → then **engineer developability on the confirmed
binders** (N-methylation), NOT a hard 2D gate that zeros the pool. The engineerable panel below is the set
worth carrying into the N-methyl-scan + 3D-permeability pass.

## Deliverables
- `research/guangzhou_all_atom/results/pdl1_engineerability_panel.xlsx` — engineerable top-15 + all 118 + method
- `…/pdl1_engineerable_panel.json`, `…/pdl1_engineerable_all_118.json`

## Still pending (on-instance, correct rulers)
- **3D-PSA / EPSA** (conformer-based — the *correct* oral-permeability gate; 2D over-estimates).
- **MM-GBSA ΔG** (physics binding) — CPU job, launchable now.
- **Actual N-methyl-scan re-fold** (place the k N-methyls at solvent-exposed, non-transannular amides and
  re-verify binding + refold), which the BioMate `cyclic_peptide_design` N-methylation + Yudin-ADMET phases do.

## Route caveat
If the asset is **injectable** (like BMS-986189, which failed on **half-life**, not oral uptake), the
governing axis is **proteolytic stability / half-life** (DPP4 & tryptic liabilities + cyclization [done] +
albumin-binding conjugation), not oral permeability. The oral-permeability engineering above applies if the
program targets the **oral-macrocycle** white-space.

## Update — 3D-PSA (the correct oral ruler) computed for the engineerable panel (2026-09-30)
Conformer-ensemble min-3D-PSA (RDKit ETKDG macrocycle confs + rdFreeSASA polar-atom SASA), NON-methylated baseline:
- Best starting points: **d49 `ATGLVIGGVVVP` = 178 Å²**, d127 `SVTVGGIVIP` = 181, d60 `SLGTFIGVPV` = 199.
- Rest of panel 205–360 Å². **As-is none clear the ~160 Å² permeable guideline** (expected without N-methylation).
- Value: ranks the best *starting points* for the N-methyl scan (lowest baseline 3D-PSA → most likely to cross
  the permeable line once backbone donors are shielded). Results: `results/pdl1_panel_3dpsa.json`.

## Update — MM-GBSA ΔG launched (2026-09-30)
On-demand GPU (user directive) `i-0820e0ef576141ab5`, run `mmgbsa-pool-5o45-…213239Z` — self-contained
OpenMM GBn2 single-trajectory MM-GBSA over the 199-pool final_ranked CIFs; streams per-design ΔG to S3.

## Update — calibration on an approved oral macrocycle (2026-10-01)
Anchored the developability screen on **cyclosporine** (real ORAL systemic macrocycle, PubChem live):
- **MW 1202.6 · TPSA 278.8 Å² · HBD 5 · HBA 12 · cLogP 3.3**
- TPSA 278.8 ≫ the naive 180 "oral window" → a correct oral drug **FAILS the 2D-TPSA gate**.
- HBD 5 ≤ 6 → it **PASSES the HBD gate** — because 7 backbone N-methylations remove the donors.

**Conclusion (validates the methodology):** 2D-TPSA≤180 is the WRONG gate (it rejects a marketed oral drug);
the **HBD-floor criterion (≤6) is the RIGHT gate** — exactly the discriminator the engineerability screen
switched to. Our panel's plan (N-methylate to reach HBD≤6) is **cyclosporine's own recipe** (its 7 N-Me).
The oral bar should be stated as *HBD-after-N-methylation ≤ ~6 + chameleonic 3D-PSA*, never 2D-TPSA.
(Voclosporin is cyclosporine's analog with the same profile; its PubChem CID lookup returned a wrong
molecule so its numbers are not cited here — cyclosporine is the anchor.)
