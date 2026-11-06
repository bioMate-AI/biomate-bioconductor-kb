# αvβ6 scaffold-hop — round 1 (genus-exiting design candidates)

**Date:** 2026-10-14 · Goal: present the RGD·L pharmacophore + turn + a chelator handle on frameworks that EXIT
the Notni nonapeptide genus `Cyclo-(Arg-X1-Asp-X2-X3-X4-X5-X6-X7)` (CA2998968, see `20261014_AVB6_FTO_READ.md`),
i.e. escape route #3 (the only one that leaves the claim by construction). Data: `results/avb6_scaffoldhop_r1.json`.

## Candidates (all pass pharmacophore + handle + genus-exit checks)
| id | chemotype | representation | genus-exit basis |
|---|---|---|---|
| SH-BCY-01 | bicyclic | bicyclo[TBMB](Ac-C-RGDLAF-C-GSKG-C-NH2) | bicycle topology ≠ head-to-tail nonapeptide; loop1 keeps RGDLAF → β6 selectivity |
| SH-BCY-02 | bicyclic | bicyclo[TBMB](Ac-C-RGDLAW-C-SKG-C-NH2) | " |
| SH-BCY-03 | bicyclic | bicyclo[TBMB](Ac-C-YRGDLAY-C-GKG-C-NH2) | loop1 = Trivehexin-like pharmacophore |
| SH-BCY-04 | bicyclic | bicyclo[TBMB](Ac-C-RGDL-[dP]-F-C-HKS-C-NH2) | D-Pro turn inside loop1 |
| SH-CYC-01 | short-cyclic | cyclo(R-G-D-L-[dP]-[NMeK]) | 6-mer ring ≠ 9 → outside claim; ⚠ no aromatic flank → selectivity risk |
| SH-CYC-02 | short-cyclic | cyclo(R-G-D-L-W-[dK]) | 6-mer; one aromatic for partial selectivity |
| SH-DEP-01 | depsipeptide | cyclo(RGDLAF-[dP]-[NMeK]) with X1 amide→ester | not an all-amide peptide → format novelty |
| SH-KNO-01 | knottin | EETI-II-type cystine-knot, RGDL in loop1 | distinct ~30-mer scaffold |

## Recommendation
**Bicyclic peptide is the lead chemotype:** it (a) keeps the FULL RGDLAF pharmacophore+aromatic flank in loop1
so β6/β8 selectivity is preserved, (b) is a genuinely different framework (two loops on a TBMB core, not a
head-to-tail peptide), and (c) is radiolabelable (Lys handle in loop2). Short-cyclic trades away the flank
(selectivity risk); depsipeptide is a thin format change (higher DoE risk); knottin works but carries its own IP.

## Honest limits / dependencies (not vetted binders)
1. **Per-scaffold IP** — each format has its own estate to clear: bicycle platform (Bicycle Therapeutics), knottin
   (Cochran/Stanford αvβ6 knottins). Genus-exit from CA2998968 ≠ clear of all IP. Counsel per chemotype.
2. **Binding validation** — unproven until folded + scored. For αvβ6 this hits the MIDAS-metal wall (metal-aware
   cofold/MM-GBSA needed) or requires experimental screening.
3. **DoE** — short-cyclic/depsipeptide are closer to the claimed peptide (higher doctrine-of-equivalents risk);
   bicycle/knottin are the cleaner structural departures.

Next: pick the chemotype → if bicyclic, generate a focused loop1/loop2 library and run metal-aware folding +
a per-scaffold FTO check, OR take the lead designs to experimental binding screen.
