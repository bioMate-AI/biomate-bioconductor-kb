# ⚠️ CONFIDENTIAL — INTERNAL IP · NOT FOR ANY CLIENT-FACING MATERIAL

This folder holds BioMate's **proprietary method IP** for the peptide/macrocycle program.

## Hard rule
**Nothing in this folder — no method, recipe, model name, architecture, tool stack, or numbers —
goes into any external artifact:** the Guangzhou client deck, flyer, sales 话术, proposals, blogs, or
emails. Those state **what we deliver** + a light credibility tag only. The **how stays here.**
(Client deck lives separately at `docs/20260921_BIOMATE_PHARMA_GUANGZHOU_CLIENT_DECK.md` and has been
verified method-clean.)

## Contents
- `20260926_PEPTIDE_LLM_ARCHITECTURE_IP.md` — **architecture & IP** (challenge→resolution→claim): leverage the PepGLAD-class backbone for speed; the IP is the resolved challenges (#1 non-canonical-native representation, #3 hard closure, #4 proprietary closed-loop) + the composite system. PepGLAD = baseline-to-beat, not a derivative.
- `20260922_PROPRIETARY_PEPTIDE_IP_TECHNIQUE.md` — the proprietary technique spec and IP-claim map.
  Honest novelty calibration: multi-objective in-sampling guidance is PRIOR ART (table-stakes capability,
  not our claim); the defensible IP is **#1 non-canonical macrocycle-chemistry generation** + **#4
  closed-loop preference optimization on proprietary wet-lab data** + the composite system.
- `20260922_PEPTIDE_LLM_COVERAGE_VS_GUANGZHOU_AND_LOOP.md` — internal capability/SOTA/data-strategy map
  (DockQ numbers, paper ceiling, data-expansion plan, loop analysis). Internal only — has method + metrics.

## Related code (also internal, kept with the implementation, not in client materials)
- `research/guangzhou_all_atom/developability_guidance.py` — #2 in-sampling developability guidance (capability).
- `research/guangzhou_all_atom/` — PepGLAD launchers, permeability predictor (EnsembleCycPerm ΔPSA3D),
  eval harness. All internal.

## IP-claim posture (honest)
- **Claim the composite system**, weighting the non-obvious parts: non-canonical macrocycle representation
  (#1) + proprietary-data-driven closed loop (#4) + hard cyclic-manifold sampling in that setting (#3).
- **Do NOT claim** multi-objective guidance (#2) as novel — it is prior art; it is a capability we hold,
  not an invention.
