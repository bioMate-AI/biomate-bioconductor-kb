# Build spec — Phase 0 (knowledge collection) + Phase 1 (closed design-score-redesign loop)

**Date:** 2026-10-15 · Concrete build spec for the peptide lead-generation system, covering BOTH the
knowledge-collection foundation and the closed loop. Grounded in components built this session — this is
assemble + harden, not greenfield. Architecture rationale: `20261015_GENERATION_SYSTEM_SURVEY_AND_ARCHITECTURE.md`.

## Guiding split (recap)
- **Inside the LLM:** the proposer (candidate generation in the free space) + language/intent reasoning.
- **Outside (closed loop):** knowledge bases + hard-constraint rules + the mechanism-matched scoring verifier.
- **Pattern:** SNG — symbolic rules constrain/reject; neural generator proposes; verifier scores; loop revises.

---
## PHASE 0 — Knowledge collection (the foundation; prerequisite to the loop)

### 0.1 Target KB  (one structured record per target)
Fields: target id; mechanism tag (`metal_cofactor` + ion type, `epitope` ∈ {linear-motif, discontinuous};
drives scorer config); pharmacophore spec (motif + geometry); counter-targets (+ their structures); controls
(known binders + measured affinity, for A2 anchoring); indication.
- **Reuse:** αvβ6 (RGD·L + MIDAS Mn; counter = αvβ8/αvβ3/αvβ5; controls Trivehexin/avebehexin) and PD-L1
  (discontinuous PD-1 face; counter = PD-L2; control = 5O45 macrocycle) records are already de facto built —
  formalize them into `cyclic_llm/target_kb/*.json`.
- **Build:** a loader that configures the scorer from the mechanism tag (e.g. metal_cofactor → inject the ion).

### 0.2 Structure KB  (docking-ready, mechanism-complete, versioned)
- Curated receptor structures WITH cofactors/metals, waters/glycans stripped, protonated — e.g. our
  `avb6_ourstructure_v1.cif` (metal-complete) and the 5O45 PD-L1 receptor. Store per target + counter-target.
- **Build:** a prep pipeline (the extraction we did for v1) + an ion-transplant/metal-aware fold recipe (validated
  this session: controls coordinate MIDAS). Version receptors; ensembles later.

### 0.3 Patent / FTO KB  (the "generate outside the estate" capability)
- **Claim layer:** structured claim representations — genus formula + per-position allowed-residue enumerations
  (our CA2998968 read is the template: `Cyclo-(Arg-X1-Asp-X2-X3-X4-X5-X6-X7)` + X-lists). Function:
  `in_claim(candidate) -> {inside | literally-outside + DoE-risk}` — exactly the acceptance_gate.H8 logic, generalized.
- **Compound layer:** patented-compound DB (SureChEMBL / Google Patents Public Datasets, InChIKey/sequence index)
  for a dissimilarity score (precedent: AAAI'24 patentability-constrained generation).
- **Build:** ingest the relevant estate per target; expose `fto_score(candidate)` = (claim-scope verdict,
  nearest-patented distance). This is a real ingestion/curation task — the biggest Phase-0 lift.

### 0.4 Verifier stack  (the multi-objective reward; mechanism-matched)
Wrap the scoring modules we built into one `score(candidate, target_kb) -> dict` with control-anchoring (A2):
- binding: metal-aware cofold (Boltz-2 + ion entities) → MM-GBSA (mechanism-matched; metal retained);
- selectivity: counter-target cofold+MM-GBSA → gap;
- site fidelity: groove-occupancy vs control pose;
- geometry: pharmacophore-presentation triage (RDKit overlay + clash + key-contact distance — the SL-v3 check);
- developability: hydrophobicity/aggregation/liability proxies;
- FTO: §0.3.
- **Hard rule:** controls scored every batch; if controls don't recover known order → scores inadmissible.

---
## PHASE 1 — Closed design-score-redesign loop

### 1.1 Generator (proposer; inside the LLM)
- Peptide generator = our HELM/sequence generator (rule-constrained decoding) and/or BoltzGen for structure-based
  binders. **SNG pattern:** the symbolic rules (pharmacophore + FTO claim-scope + developability) are passed as
  HARD constraints so candidates satisfy them *by construction*, and violators are rejected pre-scoring. Generator
  explores only the free positions (flanks, scaffold, ncAA) — never re-litigates the hard scaffold.
- **Reuse:** `pharmacophore_knowledge.generation_constraint`, `acceptance_gate` as the constraint/rejection layer.

### 1.2 Optimizer (the loop)
- `propose → score (§0.4) → select/revise → repeat`. Two interchangeable drivers:
  (a) **RL / sample-efficient search** (REINVENT4 / Saturn-style: verifier = reward; Augmented-Memory sample
  efficiency) — for breadth;
  (b) **LLM-in-the-loop revise** (propose, read the verifier's failing objective, redesign — the exact move that
  turned lactam SL-01 → SL-v3) — for targeted fixes. Use both.
- Multi-objective: optimize binding × selectivity × developability × FTO × geometry jointly (Pareto), NOT binding
  then filter (the generate-then-filter collapse to ~0 was the key failure mode).

### 1.3 Governance (Mozi pattern; the trust layer)
- Discretize the loop into verifiable stages (generate → constraint-check → score → gate → select); each stage has
  hard constraints + provenance; no candidate advances unverified. Control-anchoring and honest "relative/
  feasibility-level, not absolute" labeling baked in. This is what makes the output trustworthy for synthesis.

### 1.4 Output
Ranked, fully-gated, provenance-tagged candidate set + a CRO-ready order sheet (topology/FTO/status fields), with
the honest-limits note. Feeds the wet-lab assay; assay results return as new SAR into the Target KB (closing the
outer loop).

---
## Sequencing & reuse ledger
| piece | status | action |
|---|---|---|
| pharmacophore/liability/acceptance rules | **built** (`cyclic_llm/*`) | wrap as the constraint/rejection layer |
| metal-aware scorer (cofold+MM-GBSA, metal) | **built + validated** this session | wrap into §0.4 verifier |
| groove / counter-target / geometry checks | **built** this session | add to §0.4 |
| FTO claim read | **built** for αvβ6 (CA2998968) | generalize to §0.3 claim layer + ingest patent DB |
| metal-complete receptor | **built** (v1) | formalize Structure KB + prep pipeline |
| peptide generator | HELM-LLM / BoltzGen (exists, partial) | wire as §1.1 proposer under SNG constraints |
| optimizer loop | **manual** this session (SL-01→SL-v3) | automate via REINVENT/Saturn-style driver |
| governance | ad hoc | implement Mozi-style verifiable stages |

**Biggest new lifts:** (1) the Patent/FTO KB ingestion (§0.3), (2) automating the loop driver (§1.2), (3)
generalizing the mechanism-matched scorer config (§0.1 → §0.4). Everything else is hardening what exists.

**Honest framing:** most primitives exist in BioMate already (audit-first); the work is assembling them into a
knowledge-first, governed, closed loop with the peptide generator — the defensible build, since the OSS loops
(REINVENT/Saturn/SNG) are all small-molecule.
