# System generality across immune-mediated-disease targets

**Date:** 2026-10-15 · Internal. Answers "is the design system restricted to the two targets (αvβ6/PD-L1)?" —
**No.** The method is target-general; only the grounding was populated for two. Demonstrated by extending to a
representative set of immune-mediated-disease targets.

## What is target-general (no per-target code)
- **Generator** (`unified_cyclic_llm_v4`): trained on 5 unrelated targets (PADI4, hPCSK9, FIKK13, Aβ42, hIAPP),
  takes any target sequence/feature — already generalizes.
- **Mechanism-matched scorer config** (`scorer_config.py`): derives metal / pose-method / counter-targets from
  the KB `mechanism` tag. Proven across 8 targets below.
- **Developability + FTO/patent novelty** (`fto_score.novelty_axis` → `drug_novelty_fto`): target-agnostic.
- **Loop / reward / score()**: target-parameterized, not target-specific.

## What is per-target (the grounding to add)
- **Target KB entry** (mechanism, counter-targets, receptor) — added here for 6 immune targets.
- **Prepped receptor structure** (for physics cofold+MM-GBSA) — PDBs identified, need prep.
- **Known actives/controls** — for rule induction (else honest cold-start) and A2 anchoring.
- **FTO claim** (if a blocking patent exists) — the compound/patent novelty axis works without it.

## Demonstrated — mechanism config auto-generalizes
| target | disease | epitope | metal | pose | counter |
|---|---|---|---|---|---|
| avb6 | PDAC | linear-motif (RGD.L) | Mn @ β6 MIDAS | cofold, dock-prepose ok | avb8/avb3/avb5/a5b1 |
| pdl1 | IO | discontinuous | — | cofold required | pdl2 |
| **a4b7** | IBD/UC | linear-motif (LDV) | Mn @ β7 MIDAS | cofold, dock-prepose ok | a4b1 |
| **lfa1** | psoriasis/MS | I-domain MIDAS | Mg @ αL I-domain | cofold | mac1 |
| **tnfa** | RA/IBD/psoriasis | discontinuous | — | cofold required | ltα |
| **il17a** | psoriasis/AS | discontinuous | — | cofold required | il17f |
| **il23** | psoriasis/Crohn's | discontinuous | — | cofold required | il12 |
| **il6r** | RA | discontinuous | — | cofold required | — |

The integrin targets correctly get the metal injected (the αvβ6 lesson generalizes to α4β7/LFA-1); the cytokine
PPIs correctly get no-metal + cofold-required. Zero code change — all from the KB mechanism tag.

## Per-target readiness for full physics/scoring
All 6 new targets are **cold-start** (KB `examples.actives = []`): rule induction abstains until actives are
added; physics needs the receptor prepped (PDBs listed in each KB entry, marked "needs prep"); the
compound/patent novelty axis and mechanism config already run. The αvβ6/PD-L1 pair remains the lead program
(prepped receptors + controls + an in-flight physics-volume run).

## Honest scope
"Test ALL immune-mediated-disease targets" = extensible by adding KB entries (any target is one JSON + a receptor
away); this covers IBD, UC, psoriasis, RA, AS, MS, Crohn's. Full de-novo generation for the non-RGD cytokine
targets uses the sequence-conditioned generator (not the RGD scaffold), which is the generator's native mode.
