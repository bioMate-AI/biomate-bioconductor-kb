# Generation-system — detailed progress + next item list

**Date:** 2026-10-15 · Detailed state of the peptide lead-generation system build and the prioritized next items.
Code lives in `research/guangzhou_all_atom/cyclic_llm/`. Design refs: the five 20261015 architecture/spec docs.

## Built so far (working code, verified)
| component | file | what it does | verified behavior |
|---|---|---|---|
| **Target KB** | `target_kb/{avb6,pdl1}.json` | per-target: mechanism tag (metal? epitope?), controls, counter-targets, labeled actives/non-actives | loaded by induction + score |
| **Rule induction (SNG L1)** | `rule_induction.py` | HELM→predicates; greedy discriminative-conjunction learner induces `binder(X):-...` from few actives | avb6: `has_rgd, has_rgdl, flank_aromatic_p1, flank_aromatic_p7` — 3/3 pos, 4/4 neg, 0 err (reproduces hand-gate from data); pdl1: noisy at 1 active (honest cold-start) |
| **FTO claim layer** | `fto_kb/ca2998968.json`, `fto_score.py` | structured genus claim; `in_claim` maps candidate→X1–X7 → INSIDE / literally-OUTSIDE(pos)+DoE / OUTSIDE(form); + patent seq-identity | avebehexin INSIDE; 2Nal flank OUTSIDE-X4 MED; Ser@X3 HIGH; 7-mer OUTSIDE(form) MED; lactam OUTSIDE(form) LOW |
| **Rule-conditioned generator (SNG L2/L5)** | `rule_conditioned_generator.py` | conditions on induced rule + KB mechanism; satisfies by construction; **rejects rule-violators AND patent-INFRINGING**; ranks survivors by DoE then patent-id; emits (H,X) | all-canonical (genus) auto-rejected; survivors = ncAA-flank, MED DoE, ranked |
| **Consolidated score() / reward** | `score.py` | merges cheap tier (rule, FTO, developability) inline + expensive-tier hooks (binding dG, selectivity gap, groove, geometry from GPU pipeline); hard-gate verdict + rank key | avebehexin gate=False(infringing); clean ncAA gate=True; di-2Nal gate=False(greasy+rule) |
| **Closed optimizer loop** | `loop.py` | `propose (gen_avb6) → score() → select (freeze gate-passers) → revise → repeat`; revise = deterministic, score-record-reading repair operator (honest stand-in for the LLM-revise move) that reads the failing objective and applies one targeted free-position edit; trace distinguishes revised/converged/abandoned | 3 deliberately-failing seeds (infringing, greasy, rule-fail) all converge into the gated set in 2 rounds; **0 abandoned**; final = 5 FTO-clean MED-DoE de-greased candidates, Pareto-ranked by `score.rank_key` |
| **Neural proposer (SNG L2 neural)** | `neural_generator.py` | uses the unified_cyclic_llm_v4 ckpt to PROPOSE free-position chemistry: scores each scaffold macrocycle's likelihood under null-target + `<p_hi>` permeability, samples free-position triples ∝ likelihood (temperature = exploration), then the same rule+FTO+dev constrain+reject; same `(H,X)` interface; enumeration fallback if torch/ckpt absent | backend=`neural (unified_cyclic_llm_v4)`; model sharply prefers 2Nal flanks (permeability); temp 1.0→5 / 2.0→19 survivors of a 62-clean ceiling; `loop.py --neural` converges to 7 gated, 0 abandoned. Honest: v4 NOT trained on avb6 → signal is developable/permeable chemistry, not affinity; palette = model-known ∩ gate-known monomers |
| **Physics auto-dispatch (expensive tier)** | `physics_dispatch.py`, `score.py` `tier='full'` | READS existing MM-GBSA/counter/groove artifacts (no GPU run); joins HELM→design-ID→result; **A2 control-anchoring at receptor level** (admissible only if a control row anchors the receptor's ΔG scale — direct or inherited by a same-receptor sibling run); groove control-independent; geometry pending (no artifact) | K-05 → binding −39.86 (A2 direct, ctrl #2/14), selectivity −15.27, groove pending (G1 groove doc-only); G2 A02 → binding −28.17 (A2 inherited), selectivity +14.11 (NOT selective, matches 0/8), groove 0.733; novel avb6 HELM → all pending (never folded) |
| **Mechanism-matched scorer config** | `scorer_config.py` (+ `physics_dispatch` gate) | derives the scorer config from the KB `mechanism` tag: metal to retain (integrin MIDAS Mn vs none), pose method by epitope (linear-motif → dock-prepose-ok; discontinuous → cofold-required), counter-targets, metal-complete receptor, controls; physics admissibility now gated on `mechanism_compliant()` (replaces the hard-coded VOID list) | avb6 metal-free run → non-compliant ("requires Mn at β6 MIDAS; run does not record the metal"); **synthetic metal-aware + control-anchored avb6 run → admitted automatically** (unlock proven); pdl1 (no metal) unchanged |

## Architecture as realized (SNG pattern, working)
- **Symbolic (outside LLM):** induced rule (L1) + FTO claim constraint + developability — deterministic, cheap,
  used to CONDITION generation + REJECT violators (L2) + emit (H,X) (L3).
- **Neural (inside LLM):** the proposer — now the unified_cyclic_llm_v4 model (`neural_generator.py`, `loop.py
  --neural`), proposing free-position chemistry by permeability-conditioned macrocycle likelihood; the rule-
  constrained enumeration remains the default/fallback. (Honest: target-agnostic for avb6 — see built table.)
- **Verifier/reward:** `score()` — cheap tier live; expensive tier (metal-aware cofold+MM-GBSA, counter-target,
  groove, geometry) hooks into the GPU pipeline results we built this session, control-anchored (A2).

## Next item list (detailed, prioritized)
1. ~~**Replace the enumeration stand-in with the neural peptide generator (Phase 1.1).**~~ **✅ DONE — `neural_generator.py`.**
   - Wired the unified_cyclic_llm_v4 model as the proposer: permeability-conditioned macrocycle likelihood over
     the scaffold's free positions, temperature-controlled sampling, same rule+FTO+dev reject+rank, same `(H,X)`
     interface; enumeration fallback. `loop.py --neural` runs it. **Remaining for this item:**
     (a) **palette expansion** — the model knows 363 ncAA monomers but the neural palette is restricted to those
     the symbolic gate already classifies correctly (F/Y/W/Nal; A/G/S/Aib/Abu); expanding to exotic aromatic ncAA
     (3Pal, Bal, Bn_Gly, Ala(indol-2-yl)…) needs a **vetted monomer-property table** (aromaticity + hydrophobicity
     FP + FTO homolog) added to `acceptance_gate`/`fto_score`/`score` — a data task, do NOT guess values;
     (b) **target-aware avb6** — v4 is not trained on avb6, so today's neural signal is developable/permeable
     chemistry, not affinity; a BoltzGen/affinity-conditioned proposer is the real target-aware upgrade.
2. ~~**Close the optimizer loop (Phase 1.2).**~~ **✅ DONE — `loop.py`.**
   - Built the loop HARNESS: `propose → score() → select (freeze gate-passers) → revise → repeat`, returns the
     Pareto-ranked gated set + a per-round revise trace. The `revise` operator is the deterministic,
     score-record-reading repair (honest stand-in for the LLM-revise move); it slots out for driver (a)
     REINVENT4/Saturn RL with `score()` as reward, or (b) the neural/LLM revise, when those land.
   - Verified: 3 deliberately-failing seeds (infringing / greasy / rule-fail) converge into the gated set,
     0 abandoned. **Remaining for this item:** the learned drivers (RL policy or LLM revise) replacing the
     deterministic repair — folds into items #1 (neural generator) and #8 (own-LLM RLVR).
3. ~~**Expensive-tier integration into score() (Phase 0.6).**~~ **✅ DONE — `physics_dispatch.py` + `score(tier='full')`.**
   - Auto-dispatches admissible MM-GBSA/counter/groove RESULTS into the four hooks, A2-gated at the receptor level
     (inadmissible if no control anchors the receptor; avb6 VOIDed). **Remaining for this item:**
     (a) **produce admissible avb6 physics** — needs the metal-aware MM-GBSA run (retain+parameterize MIDAS Mn),
     control-gated; receptor asset `results/receptors/avb6_ourstructure_v1.cif` exists, the control-gated ranking
     is still a TODO (folds into #4 mechanism-matched scorer: inject metal for integrins);
     (b) **G1 groove artifact** — K-05's groove is doc-only (0.93); write a machine-readable G1 groove JSON so the
     dispatcher can fill it; (c) **auto-launch** for a gate-passing candidate with NO result yet (dispatch the GPU
     job, not just read) — currently read-only by design (spot-cost discipline).
4. ~~**Mechanism-matched scorer config (Phase 0.7).**~~ **✅ DONE — `scorer_config.py`.**
   - KB `mechanism` tag → scorer config (metal, pose method by epitope, counter-targets, receptor, controls);
     physics admissibility now gated on `mechanism_compliant()` not a hard-coded void list. **Remaining (the real
     GPU work, out of band — spot-cost discipline):** produce the metal-aware (Mn@β6-MIDAS), control-anchored
     αvβ6 MM-GBSA run — the config declares exactly what it must record (`metal:"Mn"` + metal-complete receptor +
     Trivehexin/avebehexin control), and the dispatcher will admit it automatically (unlock proven on a synthetic
     run). Also: produce integrin counter-target (avb8/avb3/avb5/a5b1) runs so selectivity can be computed for avb6.
5. **Patent/FTO compound layer (Phase 0.5 follow-on).**
   - Ingest SureChEMBL / Google Patents Public Datasets → real nearest-patented dissimilarity (replace the
     known-compound seq-identity stub). Add PD-L1 (BMS macrocycle estate — source-verify) + counter-integrin patents.
6. **Real ILP (method upgrade).**
   - Swap the greedy learner for Popper/Aleph with background theory + recursion; richer negatives per target
     (pdl1 cold-start needs more non-actives). Extend induction to FTO/developability/mechanism rule families.
7. **Governance (Phase 1.3, Mozi pattern).**
   - Verifiable stages + provenance + honest "feasibility-level, not absolute" labels on every output.
8. **Own-LLM track (parallel).**
   - (B) continue DB-gold SFT (routing/decomp/findings); (A) stand up the peptide/HELM generator; then RLVR with
     `score()` as reward once the loop produces volume. Always validate vs frontier on the narrow slice.

## Honest state
The full loop skeleton is now built and verified end-to-end: **neural proposer** (`neural_generator.py`, v4 ckpt)
→ **score()** (cheap deterministic tier + **auto-dispatched expensive physics**, A2-gated) → **select** → **revise**
→ repeat (`loop.py`, 0-abandoned convergence). Remaining labeled stand-ins / known gaps, all documented in the
next-item list: the revise operator is a deterministic repair (not a learned RL/LLM policy — #2-remainder/#8);
the neural proposer is target-agnostic for avb6 and restricted to a gate-known monomer palette (#1-remainder);
the expensive tier reads results only — there is **no admissible avb6 ΔG yet**, but the reason is now principled:
the mechanism-matched config (`scorer_config.py`, #4) requires Mn@β6-MIDAS and the existing avb6 runs are
metal-free, so they are non-compliant; a metal-aware + control-anchored run will be admitted automatically when
produced (the one remaining piece is the GPU run itself, out of band). G1 groove is doc-only (#3-remainder).
Physics scores remain relative/feasibility-level and control-anchored; the wet-lab assay is ground truth.
