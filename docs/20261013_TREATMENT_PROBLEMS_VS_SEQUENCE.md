# What a new treatment must solve, and how much of it the sequence can carry

**Date:** 2026-10-13 · The problem set a new therapeutic (αvβ6/PD-L1 cyclic-peptide radioligand) must resolve,
mapped to the peptide-sequence design levers — and, honestly, which problems the sequence cannot touch.

## The problem set (binding is 1 of ~11)
1. **Target validation** — is modulating αvβ6/PD-L1 actually therapeutic in the indication?
2. **Potency** — affinity / kinetics.
3. **Selectivity** — vs off-targets (αvβ8/αvβ3/αvβ5/α5β1; PD-L2) AND vs normal-tissue target expression.
4. **Functional efficacy** — binding ≠ cytotoxic delivery / PPI block; tumor-level effect.
5. **PK / delivery / tumor penetration** — reach the tumor at the right time; stroma barrier.
6. **Therapeutic index / dosimetry** — dose-limiting kidney; on-target-off-tumor (normal epithelia, pituitary); off-target radiation.
7. **Metabolic + chemical stability** — proteolysis, oxidation, isomerization, aggregation.
8. **Manufacturability / CMC** — reproducible ncAA-macrocycle synthesis + chelator conjugation + radiolabel at GMP scale; shelf-life / decay logistics.
9. **Patient selection** — theranostic imaging pair (Ga-68 companion → Lu-177 therapy); PD-L1 IHC.
10. **Differentiation + FTO** — better/different than existing agents, and ownable (the genus trap).
11. **Disease biology** — cold-GI/PDAC stroma + whether RLT+checkpoint converts cold→hot in patients.

## Mapping to sequence levers
| Problem | Sequence lever (in the HELM) | Coverage |
|---|---|---|
| Potency | RGD·L pharmacophore + D-Pro/N-methyl lock; flank/extended-motif tuning | FULL |
| Selectivity | aromatic flanks P1/P7; P6 specificity knob; exact RGDL register | PARTIAL (needs counter-target assay) |
| Proteolytic/plasma stability | D-residues, N-methylation, head-to-tail cyclization (no free termini) | FULL |
| Chemical/CMC liabilities | avoid Asp-Gly/Asn-Gly, Met/Trp oxidation (→Nle; bury/relocate aromatics), no free Cys | FULL |
| Radiolabeling | exactly one solvent-exposed Lys off the binding face = chelator handle | handle=sequence; chelator≠sequence |
| Renal / TI | minimize net cationic charge beyond obligate Arg + handle Lys | LIMITED — handle Lys+Arg mandatory; de-cationizing breaks function (the v2 error); real fix = construct/co-infusion |
| PK / half-life / penetration | length (shorter → faster clearance, deeper penetration) | PARTIAL — half-life matching is construct (albumin binder/PEG/multimer) |
| Differentiation / FTO | ncAA + scaffold at the free positions | LIMITED — monomer is genus-bound; novelty needs scaffold-hop/ncAA |
| Target validation, functional efficacy, patient selection, CMC-at-scale, clinical, cold→hot biology | — | NOT sequence-addressable |

## Takeaway
The sequence loop fully owns **potency, stability, the chelator-handle, and selectivity-tuning** (~4 of 11,
the "binds / stays intact / attaches" problems). The program-defining blockers — **therapeutic index /
dosimetry, target-expression homogeneity, stroma delivery, differentiation/FTO, and the cold→hot clinical
biology** — are mostly construct, modality, biology, and clinic, not sequence. The one trap: renal/TI *looks*
sequence-addressable but mostly isn't (the mandatory cationic handle), which is exactly where v2 erred.
This is the concrete form of "the moat is the construct + indication + loop, not the sequence."
