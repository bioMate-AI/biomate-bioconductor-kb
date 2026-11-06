# Session capstone — toward the best LLM + system for cyclic peptides (2026-10-06 → 10-08)

Consolidated record of a long session. Goal (user framing): **the best LLM and system for cyclic
peptides.** Everything below is committed; all results in-silico unless stated, with honest caveats.

## What was built / measured (in order)

1. **General drug novelty/FTO gate** (`drug_novelty_fto.py`, wired pre-CRO in `select_to_rfq.py`; PR #273).
   Structure (Morgan/Tanimoto vs ChEMBL/BindingDB) + patent (SureChEMBL/PubChem, POST) + sequence axes;
   peptide→SMILES MW-validated; fail-open. On the 22 CRO peptides: **20 novel, 2 dropped** (ARRGNLAPLG,
   GLFGGRGRR ≥0.85). Cutoff empirically calibrated (p99 of the novel-peptide null). Caveat: patent axis
   near-blind for de-novo peptides.

2. **Cross-target generalization = field-wide NULL, framed vs SOTA** (`20261006_CROSS_TARGET_SOTA_COMPARISON.md`).
   v3 (n=1) and **v3.1 (n=2, 3 RaPID LOTO folds) both NULL**; our OOD evals (binding 0.74→0.18, cold-start
   ≈random) sit on the same frontier as SOTA (BoltzGen ~3.3% hit, RFdiffusion ~7% w/ hotspots, Boltz-2
   excludes peptides, RFpeptides canonical-only). Honest bound: don't claim cross-target zero-shot.

3. **Structure path ceded to base BoltzGen** (`20261006_STRUCTURE_VS_BINDING_DIVISION_OF_LABOR.md`).
   Root-caused + fixed the fine-tune's lost-checkpoint failures (stalled global_step → per-epoch ckpt +
   live S3 stream); produced a 2.2 GB ckpt. LOTO smoke: **base beats our fine-tune on all 3 held-out
   targets** → use base as-is for structure, don't fine-tune; differentiate on binding.

4. **Binding selector WIN** (`20261006_BINDING_SELECTOR_WITHIN_TARGET_WIN.md`). Display-conditioned LM as a
   selector (LLR) ranks held-out binders: **PADI4 0.987, Abeta42 0.99, hIAPP 0.68**, 7–16× top-5% lift;
   the axis SOTA defers. hPCSK9 flipped in isolation (later rescued, see 7).

5. **Longitudinal trajectory denoising** (`trajectory_denoise.py`). The display round-counts (R2–R6) were
   unused (collapsed to log2fc). Recovered: **52.5% of PADI4 "binders" are jackpot artifacts**; re-eval vs
   clean binders lifts the selector **0.963→0.987**. Clean-label *training* = null (the LM is robust to the
   noise; the value is label-quality + eval, not retraining).

6. **Lever 1 — HELM/ncAA representation** (`train_helm_monomer_llm.py`). Monomer-vocab LM (387 tokens, 363
   ncAA) over CycPeptMPDB: **validity 1.0, 66% ncAA monomers, permeability-conditioning Δ+0.40**. Generates
   N-methyl/D-AA/ncAA macrocycles natively — the char-LM couldn't.

7. **Lever 2 — unified multi-target selector** (`unified_selector.py`). One target-conditioned model /
   5 targets: **matches per-target** (PADI4 0.958/Abeta42 0.983/hIAPP 0.669), **RESCUES hPCSK9 0.34→0.82**
   (its "fail" was data-isolation, corrected), **enables data-poor FIKK13 (38 binders→0.84)**.

8. **v4 synthesis — ONE model, both levers** (`unified_cyclic_llm.py`, `20261007_BEST_LLM_LEVERS_*.md`).
   Monomer-vocab, conditioned on {target, enrichment, permeability}, union-trained (CycPeptMPDB |
   display), **balanced** (else ncAA collapses to 7%). Same model: **(A)** 68% ncAA + perm Δ+0.47;
   **(B)** multi-target binding AUC 0.70–0.98 (hPCSK9 0.80). Levers compose, no degradation.

9. **System pipeline** (`design.py`). Target → generate ncAA candidates (target+hi-enrichment+hi-perm) →
   rank by binding LLR. PADI4 demo: 271 unique ncAA macrocycles ranked. The usable "best LLM + system".

10. **Move 2 (more display targets) — data-blocked.** NCBI check found no new public target-selected
    campaign (only naive yeast-display libraries). Widening the brain → deeper curation or **proprietary
    campaigns** (the moat / invert-data thesis).

## System state
data (display + 136k affinities + CycPeptMPDB) → **our LLM** (ncAA generate + multi-target binding select,
v4) × **base BoltzGen** (structure, composed) → qNEHVI MO → QC auto-loop → closed loop → FTO gate → CRO.
On-prem own-model.

## Open issues / honest frontier
- **Wet-lab closed-loop validation** — the real bar; all binding is display-trained in-silico, not affinity.
- **Widen the binding brain** — needs proprietary display campaigns (public target-selected data ~exhausted).
- **Cross-target zero-shot** — field-wide open; not claimed.
- **Composition over base BoltzGen** — needs a dual-modality target (pocket + display); documented blocker
  (`20261007_COMPOSITION_DEMO_SCOPE_AND_BLOCKER.md`).

## Key commits
FTO PR #273; e73e0829a (v3.1), bdc83a143 (SOTA cmp), c515ac7f5 (structure decision), 905c06489 (traj
denoise), 70f9ed066 (both levers), 1b141fd98 (v4 synthesis), 062182815 (design pipeline), 40c66e525 (Move-2).
Branch: cursor/tutorial-live-recording-and-report-editing-4ea7.
