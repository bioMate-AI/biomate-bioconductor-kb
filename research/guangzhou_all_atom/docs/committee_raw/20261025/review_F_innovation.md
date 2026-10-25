# Reviewer F_innovation -- x-ai/grok-4.7
_(elapsed 162s; usage {'prompt_tokens': 33629, 'completion_tokens': 9865, 'total_tokens': 43494, 'cost': 0.12472, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 1152, 'cache_write_tokens': 0, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 0.12472, 'upstream_inference_prompt_cost': 0.06553, 'upstream_inference_completions_cost': 0.05919}, 'completion_tokens_details': {'reasoning_tokens': 6380, 'image_tokens': 0, 'audio_tokens': 0}})_

## 1. VERDICT ON OUR FINDINGS

- **FEP control was a miss, not a clearance** (brief §3.1, reveal §4.1) → right, and it is the program’s best negative result. Computed −0.18 ± 0.15 vs measured −0.95, sign-only, metal-free, analytic BAR, 0.5 ns, no HREX. → Evidence still needed: the same edge after the unrestrained metal test, with replica SEM, reported as magnitude error. Do not re-litigate “expected ≈ 0”.

- **Metal was never in the site; placement fix is verified; the force field is not** (brief §3.2, metal doc §§1–8) → right. Build2 matches the pre-registered Mn1/Mn2 OK, Mn3 0.82 Å clash. → Evidence needed: `--mode post` unrestrained ≥ 1 ns (metal doc §6.4b), plus assay-buffer metal identity (metal doc §6.6, still unverified). A restrained EM is not validation.

- **Leakage, not capacity, killed the wins** (brief §3.3–3.4, reveal §3–4) → right, and under-used. Selector AUC 0.94–0.99 is circular; renal ρ +0.27 flipped to −0.26 LOTO; binding+availability 0.74 → 0.28 LODO. → Evidence needed: those three cases as frozen challenge items, not prose.

- **“Availability is the deliverable”** (reveal §6; availability doc title) → overclaimed relative to the same doc’s caveats. LODO ρ 0.40 on linear SH3 peptides is a real, modest ranker. For αvβ6/PD-L1 it is a hydrophobicity/charge proxy. Reveal §3 says “shipped as a gate”; `score.py` and `peptide_availability.py` correctly do **not** gate. “No deployable predictor existed” is **[UNVERIFIED]** and probably false: charge/grease filters are old. The Landry calibration is the contribution. → Evidence needed: one table that states non-gating, surface-proxy, ncAA approximation, and the license (CC BY-NC-ND; whether published coefficients are a derivative is **[UNVERIFIED]** — a lawyer, not a README).

- **Availability anti-aligns with the only tight SAR you own.** Coefficients in `peptide_availability.py`; A1 IC50s in brief §3.6. YY→FF is two Y→F flanks. KD(F)−KD(Y) = 4.1, so mean KD rises ≈ 0.91 and the score drops ≈ 0.23, while FF is ~5× tighter (0.17 vs 0.84 nM). → The one transferring model ranks the better binder as worse. Evidence needed: that delta computed by `predict_availability` on the four A1 HELM strings and written next to the IC50s before any ranker uses the score.

- **Permeability DPO “works”** (brief §2: ΔB +0.098, 6/6, p = 0.031, placebo +0.014; reveal §3: “placebo +0.124 vs +0.014”) → the two documents disagree. n = 6 all-positive is the sign-test floor (2/64 = 0.03125); p = 0.031 is not extra evidence. Oracle R² 0.23–0.30. Cluster-disjoint A/B still share features, so correlated error can move both. → Evidence needed: the result JSON, one number for the placebo, and a feature-shuffled or charge-only oracle that must **not** move.

- **`reward.py` still calls FEP the “TRUSTWORTHY ARBITER”** and `score.py` rank key sets pending ΔΔG to **0.0**. That is the retracted “expected null” bug, live in code. A missing file sorts like a validated zero. → Evidence needed: a unit test that pending ≠ 0 and that a build1 (metal-free) file is inadmissible.

- **`neural_generator.py` is a permeability re-ranker of ~80 triples; `loop.py:revise` is a hand rule; `methodology_close.py --signal binding` is a circular footgun** (brief §2, reveal §5) → right. Not an αvβ6 generator. Rule-constrained DPO matching unconstrained means the gate never bound.

- **Missing:** no community-runnable failure benchmark; selectivity still `pending` despite measured ratios (FF ~2494× over αvβ3 ≈ 4.6 kcal/mol **if** IC50 ratio = Kd ratio — an assumption); RFpeptides parked; `fep_production.py` has no readiness guard; `patents_checked: false`; no co-structure for A1/A2; cofold Mn3 clash 0.82 Å. SynCraft (brief §3.7) correctly kills “LLM + rules + computation” as novelty.

## 2. YOUR PROPOSAL FOR YOUR MANDATE AREA

Stop training a binder. The LLM in this codebase should be an **experiment-and-audit edit policy**: it proposes the next check or the next FEP edge, and a deterministic ledger applies it. Sequence invention stays in `rule_conditioned_generator` until a claim is admissible. With ~10 αvβ6 points you cannot fit affinity; you can score whether a claim would have survived the audit you already wrote.

Add `cyclic_llm/claim_ledger.py`:
- Claims, not scores: `rule`, `fto_legal` (must abstain while `patents_checked` is false), `developability`, `availability_proxy` (context tag required), `metal_site`, `fep_magnitude`, `selectivity`, `binding_rank`.
- Each claim is `ADMIT` / `ABSTAIN` / `REJECT` with a reason code from the audit taxonomy (circular label, charge artifact, random-CV, metal-free file, sign-only null, pending-as-zero, surface-target availability over-read).
- `binding_rank` may be `ADMIT` only if `metal_site` passed unrestrained `--mode post` **and** YY→FF absolute error is inside a pre-registered band. Until then weight 0. No MM-GBSA fallback.

Add `cyclic_llm/audit_challenge.py` and a frozen `target_kb/audit_challenge_v1.json` written **before** the scorer: the retracted cases, the three leakage flips, build1 vs build2 metal files, A1 YY/FF availability anti-alignment, FTO with `patents_checked: false`, and a planted “result file exists” spoof.

Change:
- `score.py:score` — pending stays pending; never coerce to 0.0 in `rank_key`. Do not copy `ddg_fep` unless `claim_ledger` says `ADMIT`.
- `reward.py:reward` / `build_preference_pairs` — drop the “trustworthy arbiter” path. No DPO pair whose margin comes from pending or inadmissible physics. Gate-only pairs are allowed and must be labelled feasibility, not affinity.
- `loop.py:revise` — replace flank cosmetics as the learned move with `propose_next_edit(rec) -> {abstain | repair_rule | request_metal_post | request_fep_edge}`. First legal edges only: YY→FF (magnitude) and the stubbed Asp→Ala (`EDGE_MUTS='P 2 ALA'`), and only after metal post passes. Selectivity edges wait.
- `methodology_close.py` — keep the placebo. Add two attacks: shuffle features to charge-only; inject label=conditioning. Success on those attacks is a **failure** of the harness. Disable `--signal binding` until the label is not enrichment.
- `physics_dispatch.py` (admissibility around the cited lines 144–165) — a file from a metal-free run is `REJECT`, not a number. `fep_production.py` must refuse submit without a passing post-mode JSON (the guard that today lives on the dead path).

The optimisation loop maximises **information against false admission**, not predicted affinity. Cheap oracles (rules, availability, metal validator) only decide whether an expensive edge is allowed to run.

## 3. THE ONE INNOVATION YOU WOULD BET ON

**Claim-survival ledger: predict whether a computational claim would survive your own audit, and abstain with a pre-registered coverage rule. The product is a decision record, not a binder.**

Prior art, narrowly: selective prediction / conformal abstention is established; I am not citing a peptide paper (**[UNVERIFIED]** that none exist). Multi-fidelity Bayesian optimisation of free-energy edges is a known idea (**[UNVERIFIED]** specific macrocycle papers). SynCraft already does LLM edit-sequences plus deterministic chemistry plus docking; copying it is not innovation. Reward-hacking controls exist; you already have a shuffle placebo. I do **not** know a public macrocycle benchmark whose label is retraction-class (circular NGS, charge artifact, metal-free “validation”, sign-only null, pending-as-zero) and whose only potency labels are a 4-point ELISA grid used solely as a magnitude gate (**[UNVERIFIED]** that it is absent — that is why the artifact has to be built and dated).

Why it is defensible here: the training target is the audit you uniquely have. Affinity does not transfer (your wall). Availability transfers and points the wrong way on A1. Physics is a procedure with a broken admissibility bit, not an oracle. An abstaining ledger is testable with no wet lab.

**Falsify it** if, on the frozen challenge set (half the items held out of any rule tuning), either (i) today’s `score`/`reward` already fail-closes every fatal class, so the ledger adds nothing, or (ii) the ledger misses any of {circular label, charge-only correlate, metal-free file, pending-as-zero, sign-only “pass”} or admits a binding rank while YY→FF is uncalibrated. Also falsified if a third party cannot score the JSON without your prose. A dummy “always abstain on binding” that ties you on decision utility means you built a slogan.

## 4. 30-DAY PLAN

1. **Day 1–2 (cheap, CPU).** Freeze `audit_challenge_v1.json` with expected verdicts. No scorer code yet. Gate: another person can grade it from the docs alone. If two reviewers disagree on a label, the item is dropped, not negotiated into a pass.

2. **Day 3–4 (cheap).** Run current `score.py`, `reward.py`, and `physics_dispatch` against that file. Record fail-open count. Gate: if fail-open = 0, stop the innovation (falsified). Expect failures at pending→0 and file-exists physics.

3. **Day 5–8 (cheap).** Implement `claim_ledger.py` and the `score.py`/`reward.py` fail-closed wiring. Gate: 0 false admits on the frozen set; availability LODO ρ unchanged (0.40, band 0.23–0.49); A1 YY vs FF availability delta written beside IC50s; binding weight exactly 0.

4. **Day 9–12 (cheap).** Point `methodology_close.py` placebo plus charge-only and circular-label attacks at permeability only. Gate: real ΔB stays positive **and** both attacks give |ΔB| ≤ placebo. If attacks move the evaluator, the harness is not a template — do not reuse it for claims.

5. **Day 13–16 (cheap CPU Batch; no GPU).** Rebuild/confirm metal gate on build2 artifacts; do not submit windows. Wire `fep_production.py` to require post-mode JSON. Gate: a submit against build1 and against build2-without-post is refused before a job id exists.

6. **Day 17–22 (expensive: one spot GPU equil, not a library).** Unrestrained metal continuation ≥ 1 ns. Pre-register acceptance exactly as metal doc §6.4b (every Mn keeps ≥ 2 protein/ligand O; cage holds). Gate: any UNBOUND → stop FEP for this pose; fallback is re-pose from 8TCG/4UM9/9XMM, not a smarter LLM. Also log Quigley buffer ions before calling the metal Mn.

7. **Day 23–28 (expensive: one edge, ≥ 3 replicas, not 0.5 ns independent windows if you can afford HREX; if not, label the error “optimistic BAR”).** Re-run YY→FF only. Pre-register pass as: correct sign **and** |computed − (−0.95)| ≤ 0.5 kcal/mol **and** replica SEM ≤ 0.3. The 0.5 is a proposed bar, not a literature law (1 kcal/mol “chemical accuracy” is **[UNVERIFIED]** as a universal cut). Gate: miss → `fep_magnitude=REJECT` for this FF, binding weight stays 0, no Asp→Ala, no panel. Hit → Asp→Ala is the next single edge, still no library.

8. **Day 29–30 (cheap).** Publish the challenge JSON, the ledger, the availability module with the surface-proxy caveat, and the FEP magnitude table. No candidate list. Gate: a stranger can fail your current `score()` with the JSON.

## 5. STOP DOING

- Cyclic fine-tunes of BoltzGen, UniMoMo, PepGLAD. The wall is generalisation; the deltas are null or negative.
- Display-NGS enrichment as an affinity label, including `methodology_close.py --signal binding` and the hPCSK9 “rescue”.
- MM-GBSA numbers in any ranker. Metal-free and Li–Merz runs were ruled invalid/inadmissible; 115 kcal/mol control splits are not a signal.
- Calling permeability DPO a closed αvβ6 design cycle. It never scored binding.
- Wiring `reward.py` to a trainer, or expanding `neural_generator` ncAA palette, before the ledger fail-closes.
- FEP fan-out, selectivity FEP, and CRO orders. Panel B is 0/12 RGD; panel A 0/10. Non-binders pass FTO.
- Manuscript sentences with “validated”, “anchor cleared”, “physics-verified”, “20/22 ready”. `patents_checked: false` is not FTO.
- Treating availability as the αvβ6 objective. It penalises FF relative to YY.
- More random-CV leaderboard rows.

## 6. BIGGEST RISK WE ARE MISSING

The pose is unidentified, and a better policy will launder that into confidence. There is no co-structure for A1 or A2. The cofold places MIDAS Mn 0.82 Å from Asp OD2. Assay metal identity is unverified. A magnitude miss after the placement fix still will not tell you whether the force field, the pose, or the buffer is wrong — brief §3.1 already says the −0.77 kcal/mol gap cannot be attributed. If `ddg_fep` then enters `reward()` because a file exists, the LLM will optimise a coordinate error.

Second, the stated products are extracellular radioligands. The only model that transfers (intracellular availability) moves **against** potency on the chemotype you care about (~0.23 score drop for a 5× tighter binder). Optimising the honest signal is the wrong objective for PDAC imaging. A decision system that abstains is allowed to say that. A generator is not.

Third, four ELISA points cannot identify a model. Any fit that touches them will look like SAR learning and will be leakage. Keep A1/A2 as a lock, never as a training set.