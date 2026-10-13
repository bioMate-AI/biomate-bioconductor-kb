# Construct design — where the differentiation lives (αvβ6 multivalent + αvβ6×PD-L1 bispecific)

**Date:** 2026-10-13 · Living design doc. Premise (established 2026-10-13): the αvβ6 **monomer** is a commodity
in a patented, heavily-mined genus — rule-constrained generation cannot produce a differentiated monomer
(`20261013_RULE_VS_NOVELTY_AND_PATH.md`). The sequence owns ~4 of 11 treatment problems
(`20261013_TREATMENT_PROBLEMS_VS_SEQUENCE.md`). Therefore the design novelty budget moves to the **labeled
construct** — valency, geometry, chelator/radionuclide pairing, and dual-targeting — which is also where FTO
and a real therapeutic-index story can be built. This doc specifies that work. It is design/strategy, not an
executed result; every affinity/selectivity claim is a hypothesis to be tested, and every control sequence is
flagged for primary-source verification (citation integrity).

## Relationship to the ACT application (tension acknowledged)
The ACT application was deliberately simplified to a **single-target αvβ6 macrocycle** (dropped the αvβ6×CD3
hybrid). That decision stands for the ACT lead. The constructs here are **forward R&D**, not a re-complication
of the ACT lead: **Track A (αvβ6 multivalent)** is fully consistent with the single-target simplification (it
is one target, presented multivalently — exactly Trivehexin's mechanism). **Track B (αvβ6×PD-L1 bispecific)**
is the differentiation/moat bet, explicitly gated behind PD-L1 validation and a strategic go/no-go — it is not
proposed as the ACT lead.

---

## Track A — homo-multivalent αvβ6 radioligand (de-risked, near-term)
**Rationale (proven, not speculative):** Trivehexin's clinical edge is **avidity from trimerization on a TRAP
scaffold**, not monomer novelty. The validated path to higher tumor uptake/retention is therefore valency, not
a better monomer. This is buildable the moment the warhead binding is confirmed by today's enabling order.

- **Warhead:** the cleanest-binding unit from the enabling order (avebehexin / Trivehexin monomer / R4-09),
  each carrying its single NMe-Lys ε-amine handle.
- **Scaffold / valency axis (A3):** 1 → 2 → 3 warheads on a branched chelator scaffold (e.g., TRAP = tris
  presentation with an intrinsic Ga-chelate; or a DOTA/DOTAGA-tris-maleimide/azide hub). Valency is the primary
  affinity/avidity design variable; monomer gates (H1–H5) are necessary but the construct is multivalent.
- **Linker/geometry:** PEGn spacers between hub and each warhead; spacer length tunes the inter-warhead
  distance to the αvβ6 surface density. Open parameter — to be set by modeling + empirical SAR.
- **Chelator/radionuclide (A1, theranostic pair):** NODAGA/TRAP·Ga-68 (imaging companion) ↔ DOTA/DOTAGA·Lu-177
  (therapy). Chelator charge/size perturbs both binding and renal dose → score the **conjugated** construct.
- **Renal mitigation (A5, construct-level — NOT sequence):** kidney is dose-limiting; the scaffold is
  intrinsically cationic (3× Arg + 3× Lys handle in a trimer). Mitigate at the construct/clinical layer —
  chelator charge choice, optional cleavable linker, and Gelofusine / Lys-Arg co-infusion — **not** by
  de-cationizing the sequence (that was the v2 error).
- **Risk:** low — this is a known mechanism class; the only gating unknown is warhead binding (today's order).

## Track B — αvβ6×PD-L1 hetero-bispecific, avidity-gated (differentiation / moat)
**The motivated hypothesis (this is the structure-driven reason, not an ad hoc swap):** PD-L1 fails as a
*standalone* radioligand target because of the **expression sink** (broad normal/immune expression → high
background + target-mediated clearance, A6). A **hetero-bivalent construct with deliberately weak per-arm
affinity** converts that liability into selectivity:

> A cell expressing only αvβ6 **or** only PD-L1 engages one weak arm → fast off-rate → not retained.
> A **double-positive tumor cell** engages both arms → bivalent avidity → slow off-rate → selectively retained.

This is avidity-driven conditional selectivity (the same principle that gives bispecific antibodies tumor
selectivity). It directly targets two of the hardest problems — tumor **heterogeneity** (αvβ6-hi vs PD-L1-hi
subpopulations both caught) and the PD-L1 **sink** (single-positive normal tissue is gated out) — which no
monomer can touch.

- **Key design constraint (the honest tension):** avidity-gating only works if **each arm's monovalent
  affinity is weak enough** that single-target binding does not retain. That conflicts with the instinct to use
  a maximally potent αvβ6 warhead. So Track B needs an **affinity-ceiling'd** αvβ6 arm (or a geometry that
  prevents monovalent high-avidity presentation), plus a PD-L1 arm tuned to the same regime. Getting this
  window right is the core design problem — and the real IP.
- **PD-L1 arm:** a PD-L1-binding macrocycle (provenance-pending candidates K-01/02/05) — **not admissible until
  validated** (see batch spec below).
- **Geometry:** heterobifunctional hub presenting {αvβ6 warhead, PD-L1 macrocycle, one radiochelator}; inter-arm
  distance tuned to simultaneous engagement on a double-positive membrane. Modeling + SAR.
- **Risk:** higher — PD-L1 arm unvalidated, strategic PD-L1 go/no-go open, and the affinity-window is a
  nontrivial optimization. Gated behind Track B prerequisites below.

### Track B prerequisites (none shippable today)
1. **Resolve A6:** is PD-L1 a viable radioligand/avidity-arm target, or blockade-only? (Strategic go/no-go.)
2. **Validate the PD-L1 arm** via the control-validation batch (below).
3. **Define the affinity window** for both arms (modeling-led) before committing a hetero-construct synthesis.

---

## PD-L1 control-validation batch — spec (so PD-L1 can earn its own order later)
Mirrors the αvβ6 A2 logic: **no PD-L1 candidate number is admissible until the assay recovers a published
control's known affinity + PD-L1/PD-L2 selectivity in-batch.** The batch must include:

- **Published control macrocycle(s):** BMS macrocyclic-peptide PD-L1 inhibitor lineage (e.g., the BMS-986189
  class). **CITATION-INTEGRITY FLAG:** the exact sequence and Kd must be **sourced and verified from the primary
  patent/literature before synthesis — do NOT fabricate or approximate.** If no clean public sequence+affinity
  exists, PD-L1 has **no valid control** and the batch cannot proceed (same bar we applied to today's order).
- **Counter-target:** PD-L2 (P4 selectivity) + the expression-sink dosimetry model (A6) — tumor-vs-normal
  retention, not just PD-L1/PD-L2 ratio.
- **Provenance check on K-01/02/05:** confirm each is a real generator/docking output with a verifiable docked
  pose (P1/P4), not a placeholder; record source. Drop any that fail provenance.
- **Representation (A4):** full-stereochem HELM; the same representation feeds docking/MM-GBSA.
- **Chelator (A1):** same DOTA/NODAGA theranostic pairing as αvβ6, on each candidate's single handle.

Deliverable of that batch: a validated PD-L1 binding/selectivity assay + an admissible PD-L1 arm — the
prerequisite for Track B.

---

## Open questions / next experiments (modeling-led, before any construct synthesis)
1. **Track A geometry:** model warhead valency × spacer length vs αvβ6 avidity (which trimer geometry maximizes
   tumor retention). Buildable now; gated only on warhead binding.
2. **Track B affinity window:** quantify the per-arm monovalent-affinity ceiling that yields double-positive
   selectivity without single-positive retention (the core Track-B design problem).
3. **PD-L1 go/no-go (A6):** radioligand vs blockade — decide before spending PD-L1 synthesis budget.
4. **Chelator/radionuclide scoring (A1/X2):** score the **labeled** construct (peptide+chelator), not the bare
   peptide, for both tracks.

## Bottom line
Track A is the near-term, de-risked, ACT-consistent construct — buildable as soon as the enabling order
confirms a binding warhead. Track B (αvβ6×PD-L1 avidity-gated bispecific) is the genuine differentiation bet,
motivated by a real structural/avidity hypothesis rather than a monomer tweak, and correctly gated behind
PD-L1 validation and a strategic go/no-go. This is the order worth differentiating — not another monomer.
