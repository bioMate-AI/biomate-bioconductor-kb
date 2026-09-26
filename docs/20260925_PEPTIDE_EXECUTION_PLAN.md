# Peptide Model — Execution Plan (two parallel tracks)

**Date:** 2026-09-25
**Baseline:** frozen `pepglad_ldm_epoch221` (DockQ 0.557 / Consistency 0.853 / RMSD 4.29 Å — converged; base-model DockQ is done).
**Strategy (settled, IP + loop docs):** stop chasing base DockQ; value is the **loop** + **differentiated non-canonical chemistry**. Two independent tracks run in parallel; they converge only when the loop starts optimizing non-canonical outputs.
**IP posture:** leverage the PepGLAD-class backbone to go FAST; the IP is in the **challenges we resolve** (non-canonical-native representation #1, hard closure #3, proprietary closed-loop #4) + the composite system — PepGLAD is a **baseline-to-beat**, not a thing we merely extend. Full map: `INTERNAL_IP/20260926_PEPTIDE_LLM_ARCHITECTURE_IP.md`.
**Grounding:** files in `research/guangzhou_all_atom/` (PepGLAD stack) and `drug_discovery/` (shared loop primitives). Every item ships a **multi-metric, leakage-honest** acceptance (all 7 metrics; never DockQ-only).

---

## TRACK A — Pipeline / loop around the frozen checkpoint  *(no retrain; the compounding moat)*

### A1 — Verify layer on generated peptides
- **Goal:** score each generated peptide on developability, not just pose.
- **Have:** physics — `physics_verify.sh`, `physics_eval.sh`, MM-GBSA (`peptide_mmgbsa_v3verify.sh`, `launch_mmgbsa_v3verify.sh`), FEP PoC (`launch_fep_poc.sh`, `fep_hydration_poc.sh`); permeability — `permeability_predictor.py` (EnsembleCycPerm ΔPSA3D, `perm_dpsa3d.sh`, `perm_2env.sh`); scoring — `score_generation.py`, `evaluate.py`.
- **Do:** wrap these into one `verify(peptide) → {affinity, ΔG, permeability, SA, safety, uncertainty}` service callable per candidate.
- **Effort:** M. **Accept:** every generated candidate gets the full property vector + uncertainty; provenance tagged measured-vs-predicted.

### A2 — Multi-objective selection (MPO / EHVI)
- **Have:** `multi_property_selection.py`, `perm3_select.sh`; `drug_discovery/bayesian_optimizer.py` (GP-Pareto EHVI).
- **Do:** rank/select the maximally-informative next batch across affinity × permeability × SA × safety (Pareto/EHVI); reuse the small-molecule BO engine.
- **Effort:** M. **Accept:** given a generated pool, returns a Pareto-optimal shortlist; batch diversity preserved.

### A3 — QC auto-loop gate
- **Do:** reject candidates failing hard thresholds (permeability floor, SA ceiling, clash) *before* expensive FEP/MM-GBSA.
- **Effort:** S. **Accept:** cheap filters run first; expensive verify only on survivors (cost logged).

### A4 — Closed-loop preference optimization (DPO) — **the single most defensible step**
- **Goal:** fine-tune the generator on (preferred, rejected) pairs from the verify layer, then from real assay data (order → assay → ingest → retrain).
- **Do:** new `dpo_peptide_trainer.py` — pairs from A1/A2 verdicts → DPO fine-tune the frozen epoch-221 prior (TRL-style recipe; algorithm not novel, **moat = our accumulating proprietary wet-lab data**).
- **Effort:** M/L. **Accept:** DPO-tuned prior raises developable-candidate yield on the **full 7-metric panel** without diversity collapse; pairs versioned + provenance-tagged.

### A5 — Cross-target warm-start
- **Do:** adapt the survey picks (Chemprop transfer / transfer-BO priors) so a new peptide target doesn't cold-start; DrugCLIP-style pocket triage via `detect_pocket.py`.
- **Effort:** M. **Accept:** useful proposals for a new target with few measurements; evaluated on a family-disjoint split.

---

## TRACK B — Model / differentiated chemistry  *(the #1 + #3 IP moat; independent of the loop)*

### B1 — Non-canonical macrocycle **generation** (#1, biggest differentiator)
- **Have (verification only):** `launch_nmethyl_mmgbsa.sh`, `peptide_nmethyl_mmgbsa.sh`, `perm_redesign_v1.py`, `perm_generation_v3.py` — N-Me is scored/redesigned, not *generated natively*.
- **Do:** **resolve the non-canonical-representation challenge generally** — a chemistry-native encoding (NOT a fixed-residue-vocab / brittle 14→15 patch) that emits N-Me / D-AA / staples directly. **This general solution is the crown technical IP** (#1), not "extend PepGLAD's atom count." Start with N-Me (dataset in prep), then D-AA, then staples.
- **Effort:** L. **Accept:** model samples valid non-canonical macrocycles; permeability distribution shifts favorably vs canonical-only (`chemistry_permeability_analysis.py`); this is the capability generic generators lack.

### B2 — Hard cyclic-manifold closure (#3)
- **Have:** `ph_closure_guidance.py`, `launch_closure_ph.sh`, `closure_smoke.sh`, `cyclize_and_rescore.py`.
- **Do:** enforce hard ring-closure over the non-canonical rings during sampling (the concrete non-obvious IP claim).
- **Effort:** M. **Accept:** generated cycles close within tolerance without collapse/NaN (the PH-guidance gradient-scale lesson already encoded).

### B3 — DCG P1 — learned developability heads
- **Have:** `developability_guidance.py` (P0 = geometric proxies), `permeability_predictor.py`.
- **Do:** replace the P0 proxies with **learned differentiable heads** distilled from the production scorers (ΔPSA3D permeability, SA, docking/ΔG surrogate) so in-sampling guidance matches A1's verify layer.
- **Effort:** M/L. **Accept:** guided samples score better on the *real* verify metrics (not just proxies), no diversity collapse.

### B4 — RAG for the data-starved cyclic case (supporting)
- **Do:** retrieval-augment generation from the larger linear/peptide corpus (addresses the plateau's data limit without more epochs on the same set).
- **Effort:** M. **Accept:** measurable lift on held-out cyclic targets vs the frozen baseline.

---

## Sequencing & parallelism
- **Track A order:** A1 (verify) → A2/A3 (select/gate) → **A4 (DPO, the moat)**; A5 in parallel. A4 needs A1 to generate the preference signal.
- **Track B order:** B1 (non-canonical gen) + B2 (hard closure) together (they're the same chemistry); B3 (learned heads) feeds both A1 and B; B4 in parallel.
- **Convergence:** once A1 verify + B1 non-canonical exist, the loop (A4) optimizes non-canonical outputs — the full moat: *generate hard chemistry → verify → learn on proprietary data.*
- **Highest-value single move:** **A1 → A4** on the frozen checkpoint (no retrain) — turns "DockQ 0.557" into developable, decision-ready candidates + starts the proprietary-data flywheel. B1 (non-canonical) is the top *model* move and runs alongside.

## Honest gates (every item)
- Report the **full 7-metric panel**, on **leakage-filtered/family-disjoint** splits, always vs a **physics baseline** (Vina/FEP) and a **simple baseline**.
- The closed loop is unproven until a **prospective wet-lab round** shows predicted→measured lift — that is the moat and the honest limiter.
