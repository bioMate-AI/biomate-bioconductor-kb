# Cyclic-peptide architecture — rule-constrained generation + verified-reward loop (unified survey)

**Date:** 2026-10-21 · Scope: the standing architecture for the cyclic-peptide program under
`research/guangzhou_all_atom/`. This document **unifies** four partial descriptions that previously
lived apart — it does not replace them:
- `docs/20261008_SESSION_CYCLIC_LLM_SYSTEM_CAPSTONE.md` — the fullest component inventory.
- `docs/20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md` — the clearest *conceptual* split of rules vs. generation vs. reward.
- `research/guangzhou_all_atom/docs/CLOSED_LOOP_ENGINE.md` — the only explicit generate→verify→select→learn diagram (BoltzGen/physics half only).
- `docs/20261014_CYCLIC_PEPTIDE_PROGRAM_MASTER.md` — the gate/verifier pipeline + per-target state.

Written to answer one question directly: **what is the "rule constraints + generative ability" architecture we already built, component by component, and what in it is real vs. designed-but-not-run.** Candor over spin: every status below is BUILT-AND-RUN / BUILT-AND-TESTED / BUILT-NOT-RUN / STUB, and the honest gaps are §6.

---

## 0. The architecture in one picture

> **Rules constrain → the model generates inside the constraint → physics/execution verifies → the verdict becomes a reward → the model learns from the reward.** The rules and the generator are not alternatives; they are composed. The moat is this composition + the verified-reward data it manufactures, not any single model.

```
          RULE CONSTRAINTS                      GENERATIVE                      VERIFIED REWARD
  (acceptance_gate, experience_kb/medchem_kb,  (own cyclic LM v2→v4 +          (score → reward → pairs → DPO)
   fto_score, pharmacophore, scorer_config)     selector; rule-constrained
                                                 SNG generator; BoltzGen)
            │  constrain-at-generation               │                                │
            ├───────────────> fixed scaffold + palette + in-gen reject ──> candidate HELMs
            │                                                                     │
            │  filter-after-generation                                           ▼
            └───────────────> score() hard gate ∧ FTO ∧ developability ──> physics_dispatch (admissible only)
                                                                                  │
                                                                                  ▼
                                               reward() [gate dominates; FEP ΔΔG primary] 
                                                                                  │
                                                                                  ▼
                                       build_preference_pairs → DPO pairs → Diffusion-DPO close-back
                                                                                  │
                                                           (revise / retrain)  ◄──┘
```

## 1. Three generative tracks — kept deliberately separate

1. **Track 1 — the "own" cyclic LLM.** Sequence/HELM/monomer language models conditioned on
   **mRNA-display NGS enrichment** (the binder signal that scales), culminating in the unified v4 model
   + the target-conditioned **selector**. Its one strong, held-out result is **within-target binder
   ranking (AUC ≈ 0.96, ~15× top-5% lift)**; cross-target transfer is **NULL** (§6.5).
2. **Track 2 — the rule-constrained symbolic+neural generator loop (SNG).** An induced rule `H` + KB
   mechanism *constrain generation by construction*; `score()`/`reward()` verify; reward → DPO pairs.
   This is the "rule constraints + generative ability" architecture proper.
3. **Track 3 — adopted BoltzGen.** Used **unchanged** (generate→verify→select). A cyclic fine-tune was
   tried and **regressed** cross-target (Δiptm −0.16; all-atom FT flat +0.0097 DockQ), so BoltzGen stays
   a fixed structure generator — the program differentiates on *binding*, not structure.

Tracks 1 and 2 connect: the Track-1 v4 checkpoint (`runs_helm/unified_cyclic_llm_v4.pt`) is the neural
proposer that Track-2's `neural_generator` loads; Track-2's rules wrap it.

## 2. GENERATIVE layer

| File | Role / signal | Status |
|---|---|---|
| `cyclic_llm/rule_conditioned_generator.py` (`gen_avb6`) | Symbolic proposer; **rules constrain by construction** (fixed scaffold `cyclo({p1}-R-G-D-L-{p6}-{p7}-[dP]-[NMeK])`, curated ncAA palettes, in-gen `predicates`/`avb6_gate`/`fto` reject) | BUILT-AND-RUN |
| `cyclic_llm/neural_generator.py` (`gen_avb6_neural`) | Replaces enumeration with the v4 LM: samples free-position triples ∝ log-likelihood under permeability conditioning, then the **same** symbolic constrain+reject; enumeration fallback | BUILT-AND-RUN |
| `cyclic_llm/propose.py`, `scaffold.py` | Generic spec-driven proposer (motif+scaffold → scaffold-conditioned; else de-novo on receptor seq) — the non-metal/PPI path (PD-L1, autoimmune portfolio) | BUILT |
| `cyclic_llm/train_cyclic_llm_v2.py` | nanoGPT LM (~few M params), display-NGS enrichment control tokens; PADI4 RaPID ~370k | BUILT-AND-RUN |
| `cyclic_llm/train_cyclic_llm_v3.py` / `_v3_1.py` | Cross-target probes (target-feature + enrichment; LOTO) | BUILT-AND-RUN → **NULL cross-target** |
| `cyclic_llm/train_helm_monomer_llm.py` | ncAA-native monomer LM, permeability-conditioned (validity 1.0, ncAA-frac 0.66, perm Δ+0.40) | BUILT-AND-RUN |
| `cyclic_llm/unified_cyclic_llm.py` (**v4**) | One model: monomer vocab + {target, enrichment, permeability} conditioning; n_train 1.15M; multi-target binding AUC 0.70–0.98 | BUILT-AND-RUN |
| `cyclic_llm/unified_selector.py` | Target-conditioned selector (LLR hi−lo); **the within-target WIN** (AUC PADI4 0.958 …; rescued hPCSK9 0.34→0.82) | BUILT-AND-RUN |
| `cyclic_llm/design.py` | v4 interface (`load`/`loglik`/`generate`); target→ranked ncAA macrocycles | BUILT-AND-RUN |
| `boltzgen_cyclic_convert.py` + `boltzgen_*` | Adopt BoltzGen (converter round-trip 5/5); used unchanged | BUILT-AND-TESTED; FT ceded |

## 3. RULE-CONSTRAINT layer

| File | Role | Status |
|---|---|---|
| `cyclic_llm/acceptance_gate.py` (`avb6_gate`, `raw_tokens`) | αvβ6 design requirements as computable hard gates H1 RGD / H2 RGDL / H3 D-Pro+N-methyl turn / H4 aromatic flanks / H5 single Lys handle → `PASS_H1_H5`; ncAA-aware; shared HELM tokenizer | BUILT-AND-TESTED |
| `cyclic_llm/rule_induction.py` (`predicates`, `induce`) | ILP-style discriminative conjunction → the induced rule **H** (the "H" in SNG's (H,X)) | BUILT |
| `cyclic_llm/pharmacophore_knowledge.py` | Hard pharmacophore gate + `generation_constraint(target)` — the contract a constrained decoder must enforce (origin: the display LM learned a shallow Arg-Gly correlate, 0/12 Asp) | BUILT |
| `cyclic_llm/knowledge_liability_flags.py` | Zero-compute textbook CMC/radiopharmacy rules run FIRST (deamidation, isomerization, oxidation; β6-selectivity SAR; renal cationic-charge limit) | BUILT |
| `cyclic_llm/fto_score.py` | FTO/novelty: claim-genus (CA2998968 INSIDE/OUTSIDE + DoE) + compound/patent Tanimoto axis (136k ChEMBL/BindingDB + SureChEMBL); fails open with status | BUILT-AND-TESTED |
| `cyclic_llm/scorer_config.py` (`mechanism_compliant`) | Mechanism admissibility: METAL targets (αvβ6→Mn MIDAS) **require** the metal retained or the ΔG is VOID; sets pose method | BUILT-AND-TESTED |
| `cyclic_llm/medchem_kb.py` | **General evidence-grounded KB**: 5 domains (liability 1,585 RDKit alerts w/ citations; metal geometry+FF; physchem/ADMET; pharmacophore-by-class; modality heuristics) | BUILT-AND-TESTED |
| `cyclic_llm/experience_kb.py` (`resolve`) | **The resolver / single source of params+gates.** Wraps medchem_kb + instance assets into provenance-validated `KBEntry`s; **hard-evidence invariant** (no ref → quarantined `candidate`, never served; config exempt). `resolve()` → `{tool_params, eval_criteria(hard/advisory), provenance, candidates}` | BUILT-AND-TESTED |
| `cyclic_llm/score.py` | Consolidated verifier: cheap tier (`rule_pass` ∧ not-infringing ∧ developability = **hard gate**) + expensive tier dispatch; `rank_key` | BUILT-AND-TESTED |
| `cyclic_llm/target_spec.py` | Generic target engine (metal is just a `cofactors` field, not special-cased); ~20 target specs | BUILT-AND-RUN |

## 4. Where rules meet generation — the architectural crux

This is the part the preferred architecture lives or dies on, and we implement it **both ways on purpose**:

- **Constrain-at-generation (violators never emitted).** The fixed scaffold encodes the mechanism/
  pharmacophore; the palette is restricted to rule-satisfying + model-known monomers; and inside the
  generator (`gen_avb6` / `_constrain_reject`) `rule_induction.predicates`, `acceptance_gate.avb6_gate`,
  and `fto_score` reject before a candidate leaves. `pharmacophore_knowledge.generation_constraint` is the
  contract a constrained *decoder* is meant to enforce for the neural path.
- **Filter-after-generation (verification → learning signal).** `score.hard_gate_pass`,
  `physics_dispatch` admissibility, and `reward`/ranking are post-hoc verification; their verdicts feed
  `loop.revise` (targeted repair) **and** the DPO preference signal. The loop couples the two: filter
  outcomes *become* the training signal that reshapes the next round of generation.

## 5. VERIFIED-REWARD loop — the candidate→pair→train data flow

1. **Generate** (rules constrain): `gen_avb6` / `gen_avb6_neural` / `propose`→`scaffold` → candidate HELMs.
2. **Constrain+reject in-generator**: `predicates` + `avb6_gate.PASS_H1_H5` + `fto` INSIDE-genus drop.
3. **Score (cheap)**: `score()` → `rule_pass`, `fto{verdict,doe}`, `developability`, `hard_gate_pass`, `rank_key`. Round params/gate-set come from `experience_kb.resolve(target)` (single source; cofactor-divergence assert in `loop_batch`).
4. **Score (expensive, `tier='full'`)**: `physics_dispatch.physics_for` fills `binding_dG`/`selectivity_gap`/`groove`/**`ddg_fep`** *only if admissible* (A2 control-anchor + metal gate + FEP control-edge validated); missing physics is dispatched to AWS Batch (`physics_batch`, dry-run default).
5. **Reward**: `reward.reward` → scalar. Hard gate **dominates** (1.0); **FEP ΔΔG is the preferred binding term (0.90); MM-GBSA is a weak feasibility fallback (0.45)**; selectivity first-class (0.60); pending physics = 0 (honest feasibility-level reward).
6. **Emit pairs**: `reward.build_preference_pairs` → gate-passing ≻ gate-failing (+ gated-higher ≻ gated-lower), margin = reward gap, stream `STREAM_VERIFY_SELECT`, HELM representation → `dpo_pairs.PairSet` → `target_kb/avb6_dpo_pairs.jsonl`.
7. **Execution-graded reward (real runs)**: on cofold/MM-GBSA/assay completion, `loop_grade_bridge.record_scored_run` grades outputs against the `cyclic_peptide_*` contracts and persists a scalar reward in `graded_run_store` — the ground-truth reward that later replaces the feasibility verifier.
8. **Train (close-back) — NOT YET RUN**: `PairSet.to_trl_records()` → TRL DPO (sequence LM) **or** `dpo_peptide_trainer.train_dpo` **Diffusion-DPO** for the in-house latent-diffusion generator (PepGLAD; no tractable seq log-likelihood → denoising-MSE NLL proxy, RNG-synced). CPU-selftested; gated on volume + GPU.

Supporting reward-loop files: `loop.py` (CPU deterministic optimizer; `revise` = symbolic stand-in),
`loop_batch.py` (one round w/ real Batch physics), `physics_batch.py` (dispatch seam),
`c2_retro_loop.py` (**the one demonstrated "the loop learns" result** — retrospective, on real measured
affinity, UCB/Thompson, cluster-disjoint cut; distinct from the generator RLVR which is unfed).

## 6. Honest status — built vs. designed-but-not-run

1. **Gradient RLVR/DPO on the generator — NOW RUN on public measured data (2026-10-21).** Previously the single biggest unexecuted piece (only `SIMULATED_*` artifacts existed). `cyclic_llm/methodology_close.py` closes it for real: the collected v4 cyclic LM is DPO-tuned against a VERIFIED reward (oracle on the collected **CycPeptMPDB measured permeability**, 8,462 peptides), checked with an **independent** oracle on a disjoint half (anti-circular). Result (`results/methodology_close_result.json`): independent-evaluator mean **−5.669 → −5.418 (Δ +0.251)**, essentially equal to the reward-oracle gain (Δ +0.248) — a genuine shift toward higher *measured* permeability, **not** reward-hacking — validity 1.0, diversity/novelty preserved (521 pairs, 150 DPO steps). The methodology is thus demonstrated on real data, decoupled from αvβ6/FEP. Still open: the **structure**-generator close (PepGLAD Diffusion-DPO), and running this on affinity (`binding_affinity_v1`, 28,875) / at `--big` scale. The retrospective *acquisition*-learning edge is separately demonstrated in `c2_retro_loop.py`.
2. **`loop.revise` is a symbolic stand-in**, not a learned policy (REINVENT4/Saturn swap noted-not-built).
3. **Physics tier is read-only / pending for αvβ6.** No admissible binding ΔG yet (metal-free MM-GBSA voided; metal-aware MM-GBSA + the FEP control edge pending) → expensive reward terms are 0 in practice → reward is feasibility-level only today.
4. **Two of three DPO streams empty.** Only `STREAM_VERIFY_SELECT` (the loop's own ranking, not new ground truth) is fed; `ACTIVITY` (ChEMBL/ExCAPE) and `EXPERT` (within-patent hard negatives + customer accept/reject — the stated moat) are unwired.
5. **Cross-target generalization unsolved (NULL/NEGATIVE)**; the neural generator is target-agnostic for αvβ6 (conditions on permeability/null-target, not αvβ6 affinity). The strong result is within-target selection only.
6. **`experience_kb._llm_rag_call` is a dead seam** (returns None); `register_experience_kb.py` is DRY-RUN (KB not persisted to the production workflow DB locally).
7. **Docking never scored** (`docking_gate` = `prepared_not_scored`; no fabricated ΔG). Trusted discriminator is MM-GBSA.
8. **FTO caveats**: the αvβ6 FTO-genus KB entry is QUARANTINED (patent id unverified); patent axis is near-blind for de-novo peptides.
9. **No wet-lab validation anywhere** — all results in-silico.

## 7. What this means

The **rule-constraint layer is real and tested**; the **generative layer is real with honest
within-target-only wins**; the **reward loop is built and CPU-selftested end-to-end but has never run as
a closed gradient loop on real volume.** So the architecture you preferred exists and is sound in every
link — the one unexecuted edge is the final close (gradient DPO/RLVR fed by verified reward at volume),
which is gated on (a) admissible physics for αvβ6 (the FEP control edge) and (b) preference-pair volume.
The defensible, publishable kernel today is the within-target display-enrichment selector (AUC 0.96) plus
the rigorous cross-target negative; the moat is the composition in §0 + the proprietary verified-reward
data the loop would manufacture — not any single model.

*Sources: the component files under `research/guangzhou_all_atom/` (read 2026-10-21) and the four docs in
the header. No training/eval/GPU was run to produce this document.*
