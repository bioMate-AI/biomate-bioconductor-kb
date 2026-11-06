# Cyclic-peptide program — master record (method, factors, decisions, data index)

**Date:** 2026-10-14 · Living master doc consolidating the αvβ6 (radioligand) + PD-L1 (blocker) cyclic-peptide
work. Captures the pipeline, the factors/gates considered at each stage and *why*, the per-target decision log,
honest caveats, and pointers to the detailed docs + data files. Detailed docs are authoritative for specifics.

---
## 1. Scope & top-level decisions
- **Two targets, two modalities, two molecules — no fusion.** αvβ6 = targeted **radioligand** (RGD macrocycle +
  chelator). PD-L1 = **blocker** (PD-1/PD-L1 PPI inhibitor, no chelator). If combined, it is a **regimen**
  (radio-immunotherapy), NOT a bispecific (decided 2026-10-13: a delivery warhead + a blocker on one molecule
  is modality-incoherent). See `20261013_PDL1_BLOCKADE_SINGLE_TARGET.md`, `20261013_CONSTRUCT_DESIGN_*` (HALTED).
- **PD-L1 reframed radioligand→blocker** (2026-10-13): removes the two radioligand objections — expression-sink
  (fine for a blocker) and the mandatory cationic chelator handle (not needed) — and opens design freedom.

## 2. The gated pipeline (and the factor each stage tests)
Generation → cofold → MM-GBSA → gates, run on AWS GPU (spot-first, on-demand fallback, self-terminating).
| stage | tool | factor tested | why |
|---|---|---|---|
| Generation | rule + sampler | mechanism validity / design hypothesis | get candidates that *could* bind |
| Developability pre-filter | residue proxy (Fauchère-Pliska, liabilities) | solubility/aggregation/oxidation/charge | docking over-rewards greasy burial → pre-filter kills artifacts (A10) |
| Cofold | Boltz-2 (`cyclic:true`; ion entities for metal sites) | does a plausible bound complex form | produces the pose; ipTM is NOT an affinity discriminator (saturates) |
| MM-GBSA | OpenMM GBn2 / CHARMM36m, minimized single-point | relative binding ΔG | the trusted *within-target* ranking (relative, not absolute) |
| Control anchor (A2) | controls in-batch | is the pipeline admissible | if controls don't rank strong, candidate numbers are void |
| Groove occupancy | pose contact overlap vs control | binds the *real* site, not a surface artifact | high ΔG off-site = false positive |
| Counter-target selectivity | cofold+MM-GBSA vs off-target | on-target specificity | a cross-reactive binder is unusable |
| FTO | patent claim mapping | freedom to operate | a potent, owned-by-someone-else molecule is worthless |

**Rule: gate before score** (A9) — pre-filter on gates, rank only survivors; never read gates off a score list.
Gate catalog (αvβ6 H1–H9 hard gates, PD-L1 P1–P5, cross-cutting X, additions A1–A11): `20261013_acceptance_criteria_v1.1.yaml` + `cyclic_llm/acceptance_gate.py`.

## 3. PD-L1 track (blocker) — status: 1 validated lead + 8 in final gating
- **Design:** amphipathic head-to-tail macrocycle covering the PD-1 hydrophobic groove; no linear motif → design
  by physicochemistry + structure, not a rule. Control/receptor = PDB **5O45** (PD-L1 IgV + bound macrocycle).
- **G1 (10):** cofold 14/14 (incl. control); MM-GBSA control #2/14 (A2 PASS). Gated: developability dropped the
  di-2Nal greasy artifacts; groove PASS (K-05 93%, G1-09 73%); **PD-L2 selectivity: K-05 PASS (−15 kcal/mol gap),
  G1-09 FAIL (−4.4).** → **K-05 = single fully-gated lead.** `20261013_PDL1_PRIORITIZATION_RUN.md`, `20261014_PDL1_ORDER.xlsx`.
- **G2 (24)** [to extend the order]: hard developability pre-filter (K-05 analogs + fresh). Cofold 24/24;
  MM-GBSA 24/24 (F05 −36 beats control); groove **8/8 strong tier PASS (60–80%)**; **PD-L2 selectivity: 0/8 PASS**
  — all bind PD-L2 as well or better (pan / PD-L2-preferring). **Order stays at K-05** (only selective lead G1+G2).
  `pdl1_g2_*.json`. **Finding: PD-L1/PD-L2 selectivity is the bottleneck, not affinity/developability.**
- **Factors that actually decided it:** developability (2Nal/Trp hydrophobicity artifacts), groove occupancy,
  and PD-L2 selectivity gap. ΔG alone was not trusted (over-rewards greasy burial).

## 4. αvβ6 track (radioligand) — status: FTO-blocked monomer → scaffold-hop; metal-aware pipeline just validated
- **Monomer is FTO-blocked.** `CA2998968A1/C` (Notni/TRIMT, granted, active ~2036) claims
  `Cyclo-(Arg-X1-Asp-X2-X3-X4-X5-X6-X7)` incl. multimers + chelator conjugates. Every Round-3 monomer maps inside;
  only Ser@X3 is literally outside (DoE-vulnerable). → no FTO-clear monomer/construct without a license.
  `20261014_AVB6_FTO_READ.md` (informational, not legal advice).
- **Affinity MM-GBSA was invalid** metal-free: integrin RGD binding is MIDAS-metal-mediated; the cofold dropped
  the metal → weak/positive ΔG. `20261014_AVB6_PRIORITIZATION_RUN.md`. (The deferred 5/10 setPositions cap bug
  was separately root-caused + fixed: `first/last='none'`.)
- **Our own structure (v1):** curated metal-complete receptor from 9XMM (headpiece + MIDAS/ADMIDAS/SyMBS Mn + Ca).
  `20261014_AVB6_OUR_STRUCTURE.md`, `results/receptors/avb6_ourstructure_v1.cif`.
- **Metal-aware fold VALIDATED (2026-10-14):** cofolding controls WITH 3 Mn ions → RGD Asp coordinates MIDAS Mn
  (Trivehexin 0.8 Å, avebehexin 1.9 Å); ligand-ipTM ~0.90. First physically-valid αvβ6 binding setup.
- **Scaffold-hop (FTO escape):** keep RGD·L + turn + handle, exit the nonapeptide genus. Chemotypes: bicyclic
  (lowest DoE), **monocyclic side-chain-lactam (recommended monocyclic lead)**, ring-size 7/11-mer, depsipeptide,
  knottin (own IP). `20261014_AVB6_SCAFFOLD_HOP_R1.md`, `avb6_*scaffoldhop*.json`.
- **Next:** metal-aware MM-GBSA (retain + parameterize Mn), control-gated, then rank the scaffold-hops.

## 5. Honest caveats carried throughout
- MM-GBSA ΔG is **relative within-target**, not absolute affinity; canonical-backbone approximation for ncAA at
  cofold; single receptor structure per target (PD-L1 = 5O45 only; ensemble would harden final picks); PD-L2 is a
  modeled IgV (softer than PD-L1); metal-aware MM-GBSA params (Mn) are approximate; FTO is informational, needs
  counsel + granted claims per jurisdiction + DoE. Ground truth = wet-lab binding/competition assay.

## 6. Document & data index
- **Decisions/strategy:** `20261013_RULE_VS_NOVELTY_AND_PATH.md`, `20261013_TREATMENT_PROBLEMS_VS_SEQUENCE.md`,
  `20261013_PDL1_BLOCKADE_SINGLE_TARGET.md`, `20261013_CONSTRUCT_DESIGN_AVB6_PDL1.md` (HALTED).
- **Gates:** `20261013_acceptance_criteria_v1.1.yaml`, `cyclic_llm/acceptance_gate.py`.
- **PD-L1:** `20261013_PDL1_G1_CANDIDATES.md`, `20261013_PDL1_PRIORITIZATION_RUN.md`, `20261014_PDL1_ORDER.xlsx`;
  data `pdl1_g1_candidates.json`, `pdl1_mmgbsa_results.json`, `pdl1_pdl2_counter_mmgbsa.json`, `pdl1_g2_*.json`.
- **αvβ6:** `20261014_AVB6_FTO_READ.md`, `20261014_AVB6_PRIORITIZATION_RUN.md`, `20261014_AVB6_OUR_STRUCTURE.md`,
  `20261014_AVB6_SCAFFOLD_HOP_R1.md`; data `avb6_*.json`, `receptors/avb6_ourstructure_v1.cif`.
- **Superseded/withdrawn:** `20261013_CRO_SEND_v2.csv` (WITHDRAWN), `20261013_CRO_ORDER_V4_ENABLING.*` (DROPPED).

## 7. Open / in-flight (as of 2026-10-14)
- PD-L1 G2 PD-L2 counter-screen running → final extended order.
- αvβ6 metal-aware MM-GBSA (control-gated) → then score scaffold-hops.
- Not computable here: experimental αvβ6 co-structure (program asset, lab route); per-scaffold FTO for the hops.
