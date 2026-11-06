# Composition demo (base BoltzGen × our binding selector) — scope + the honest data blocker

**Date:** 2026-10-07 · The program's product thesis is **composition**: base BoltzGen generates
structurally-designable cyclic peptides (its strength, ceded per `20261006_STRUCTURE_VS_BINDING_DIVISION_OF_LABOR.md`)
→ our display-conditioned **selector** ranks them for binding (our win, `20261006_BINDING_SELECTOR_WITHIN_TARGET_WIN.md`).
This records how a clean end-to-end demo would run, and the specific data gap that blocks the *joint*
validation — so it isn't forced with a confounded run.

## The demo (how it would work, non-circular)
1. Pick a target T. Generate N base-BoltzGen cyclic designs against T's binding pocket (`boltzgen run
   --protocol peptide-anything`, the `boltzgen_ourtarget.sh` recipe).
2. Score each design with **our T-specific selector** (`cyclic_llm_selector.py`, LLR = logP(seq|hi)−logP(seq|lo)).
3. Validation (in-silico, honest): do the **selector-high** base designs resemble the **trajectory-clean**
   T display-binder family (sequence/motif similarity) significantly more than selector-low designs? Two
   *independent* views of T-binding (structure-based generation + display-selection) agreeing is the signal.

## The blocker — no dual-modality target
The demo needs a target with BOTH (a) a cyclic-binding **pocket** to generate against, and (b) a **working
display selector**. Our five display targets don't provide both:

| target | display selector (this work) | cyclic-binding pocket available? |
|---|---|---|
| **PADI4** | **best, AUC 0.987** | **no** cyclic:PADI4 co-crystal in our set; apo/Ca structures only → pocket-builder (needs a bound peptide/ligand chain) can't define the display site; the RaPID binding site is unconfirmed structurally |
| hPCSK9 | **failed, AUC 0.34** | yes (PCSK9 is pocket-rich, many PDBs) — but the selector doesn't work, so composition is moot |
| FIKK13 | too few binders (38) | kinase, pocket plausible, but no selector |
| Abeta42 / hIAPP | 0.99 / 0.68 | amyloid peptides — aggregation targets, not a clean small-molecule/peptide pocket for de-novo design |

So the one target with a strong selector (PADI4) lacks a clean cyclic pocket, and the pocket-rich target
(PCSK9) has a broken selector. **Both halves are independently demonstrated; the joint demo needs a target
that has both — which the current data does not give cleanly.** Forcing a PADI4 run against a
literature-guessed active-site pocket would be speculative AND confounded (the display binders may bind a
different site), so it is not run here.

## Unblock paths (ranked)
1. **A display campaign against a target with a solved cyclic-binding pocket** (or pick a display target
   that later gets a co-crystal) — the clean path; dual-modality by construction.
2. **A co-crystal of a known PADI4 display binder** (e.g., from the RaPID PADI4 campaign PRJNA1188087, if a
   structure exists/is solved) → defines the PADI4 pocket at the real display site → clean PADI4 demo.
3. **Exploratory, explicitly-caveated PADI4 run**: define the PADI4 pocket from literature active-site
   residues, generate, score, and report similarity-to-clean-binders WITH the site-ambiguity caveat
   front-and-center. Suggestive only; not a clean validation. (Available on request.)
4. **Wet-lab**: synthesize selector-top base designs for a display target and assay — the real bar (closed loop).

## Status
- **Base structure half:** demonstrated (base BoltzGen designable cyclic binders; it beat our fine-tune).
- **Binding selector half:** demonstrated this session (PADI4 0.987 on clean binders; 3/4 targets strong).
- **Joint composition:** architecturally sound, **validation data-blocked** (no dual-modality target). This is
  a data acquisition / structural-biology gap, not a capability gap — and it is the honest next requirement,
  not something to manufacture in-silico.
