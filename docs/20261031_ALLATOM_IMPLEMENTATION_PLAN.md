# All-atom hybrid LLM: implementation plan (two parallel tracks) — 2026-10-29

Contract documents: `20261031_ALLATOM_LLM_PAPER_DESIGN.md` (claim H-AA, verifier ladder, baselines, controls, stop rules) and `committee_raw/20261030c/audit_gates_data_criteria.md` section D (ten-point rulebook). This plan only says WHO builds WHAT, in WHAT ORDER, against WHICH interfaces, and WHEN we stop. Nothing here changes the claim, the gate or the margins.

## 0. Rules for every workstream
1. **No compute on the owner's laptop.** Tests, fits, sampling, aggregation run on EC2 spot (or Spark if reachable). The laptop edits text/code and runs git.
2. EC2 standard: `ecsInstanceRole` (not AutoimmuneCorpusProfile), SG `sg-0de9af2d4437a8c90`, root gp3 40-120 GB, tags `project=cyclic-selector` + `Name=allatom-<workstream>`, terminate-on-shutdown, `shutdown -h +N` wall-clock cap, no bare `wait` with a background loop, per-run S3 prefix `s3://biomate-nextflow-work/cyclic_peptide/allatom/<workstream>/<run-id>/` (ONE writer per prefix), boot log to S3 within 20 s, SSM probe within 3 min, resumable, terminate at the done flag. A cost log row (instance id, type, launch/terminate, price) per instance.
3. Commit code and each pre-registration amendment BEFORE the run it governs; `git add <paths>` then `git commit -- <paths>`; no `add -A`, no `--amend`.
4. Rulebook: MDE first; margins from decisions; unit of inference = objective-family cluster x seed; controls that can fail AND pass; amendment discipline; frozen vocabulary GO / NO-GO-detectable / INCONCLUSIVE; numbers from committed files, never from memory.
5. Monitoring: each owner polls its own jobs every 3-5 minutes with bounded commands (`run_in_background`, `--cli-read-timeout 30`); the coordinator runs a heartbeat every 7 minutes; a workstream with no commit and no instance for 2 beats is nudged.

## 1. Architecture (reuse / modify / new)
| component | status | notes |
|---|---|---|
| ChemFM-1B causal LM | reuse + LoRA delta (modify) | main generator; ~860 s/1000 samples on 32 vCPU (pilot 3); validity 0.98 unconstrained |
| PeptideCLM-2 encoder (`ihlm_backbone/`) | reuse frozen | embeddings for retrieval, surrogate, diversity |
| Boltz-2 / BoltzGen / UniMoMo | reuse as-is | held-out structure verifier, final top-k only |
| MM-GBSA, FEP (`physics_dispatch.py`, `fep_production.py`) | reuse | audit tier, stage 3 only |
| PMO harness (`allatom_paper/pmo_harness.py`) | reuse (19 tests) | add `stop` verifier role |
| Rule automaton + fine-tune under the mask | NEW (U1) | hard rules as logit mask with prefix-feasibility look-ahead; soft rules as log-linear potentials |
| Goodhart-gap early stopping | NEW (U2) | three-way verifier split train / stop / held-out |
| Graded preference tuning (variance fix) | MODIFY (U3) | DPO-style rank pairs, variance filtering, KL gate |
| Retrieval-conditioned prompting | NEW wiring (I-B) | k nearest known peptides + scores in context |
| Orchestrator (loop runner) | NEW (I-A) | rounds: sample -> verify (budgeted) -> pairs -> update LoRA -> update retrieval store |
Optional, only after stage 1 passes: paired preference from within-lab pairs (U4), cost-aware surrogate gate (U5).

## 2. Interfaces (frozen first; all tracks code against these)
Written to `research/guangzhou_all_atom/cyclic_llm/allatom_paper/contracts.py` by I-A within the first 30 minutes; text here is normative until then.
- `Verifier` (existing in `pmo_harness.py`): `name`, `role in {train, stop, heldout}`, `cost_per_call`, `fit_sources: frozenset`, `__call__(smiles) -> float | None`; budget counter + cache in the harness; held-out cannot be an oracle (`HeldOutVerifierError`); `check_independent`.
- `Generator`: `sample(n, prompt_ctx, temperature, seed, constraint=None) -> list[str]` (SMILES), `logprobs(smiles_list, prompt_ctx) -> list[float]`, `load_lora(path)`, `lora_state() -> bytes`, `kl_to_reference(smiles_list, prompt_ctx) -> float`.
- `Constraint` (U1 produces): `init_state()`, `mask(state, vocab) -> bool[V]` (feasible next tokens, prefix look-ahead), `advance(state, token) -> state`, `is_complete(state) -> bool`, `soft_logits(state, vocab) -> float[V]`. Pure-Python reference implementation + vectorised version; golden tests on enumerated valid/invalid strings.
- `Retriever` (I-B): `build(store_rows)`, `query(smiles, k, exclude_docs=None) -> list[(smiles, score_dict)]`, `add(smiles, score_dict)`; blind-rule hook (`exclude_docs`) for arm G.
- `PreferenceUpdater` (U3): `make_pairs(samples, scores, margin, group_by) -> pairs, diagnostics` (fraction of zero-variance groups, rank gaps), `step(pairs, lr, beta) -> metrics` (loss, KL, weight delta).
- `StopMonitor` (U2): `update(round, train_scores, stop_scores) -> {gap, trend, should_stop}`; held-out scores never enter.
- Logging schema: one JSONL row per oracle call and per round (run id, seed, objective, verifier, smiles hash, score, calls used, round, KL, gap), uploaded to S3 every 60 s.

## 3. Workstreams (parallel), dependencies and deliverables
### Track I — integration
- **I-A Orchestrator + verifier services (owner fork 1).** Deliverables: `contracts.py`; `stop` role added to the harness with tests; verifier wrappers for tiers 0-2 (rules, physchem + SAR potential, permeability predictor A) and tier 3 (GP on source half B), each with cost and independence metadata; the round loop with resumable checkpoints; run scripts + EC2 user-data generator; a smoke run with a toy generator and the planted-optimum oracle. Depends: nothing. Done when: 19 existing + new tests pass on EC2; smoke run reproduces the planted optimum for random search and the GA baseline.
- **I-B Retrieval, encoder, structure adaptors (owner fork 2).** Deliverables: store builder (known peptides with measured values, CycPeptMPDB excluded from training data of the generator per earlier rules; target pharmacophore rules from `acceptance_gate.py`), stereo-aware Tanimoto index, PeptideCLM-2 embedding cache, prompt builder, blind-rule filter, Boltz/BoltzGen/UniMoMo thin wrappers with cost metering (no calls in this phase beyond one smoke test). Depends: contracts (Retriever). Done when: retrieval unit tests (stereo siblings, exclude_docs) and a determinism test pass on EC2.
### Track U — improve upon
- **U1 Rule automaton + fine-tuning under the mask (owner fork 3).** Deliverables: compiler from the rule spec (`peptide_sar_rules_v1.json`, hard-rule list) to a `Constraint` over ChemFM's tokenizer; golden tests (>= 2,000 enumerated valid / invalid peptide SMILES; macrocycle closure, ring >= 12, N-Me window, MW bound, PAINS prefix patterns); measured mask overhead; a fine-tune-under-mask recipe (LoRA, loss on masked softmax) with a tiny GPU smoke test. Depends: contracts (Constraint), ChemFM tokenizer. Done when: automaton tests pass, rule satisfaction of masked sampling = 1.0 on 5,000 samples, and a 200-step LoRA smoke run completes without NaN.
- **U2 Goodhart-gap early stopping (owner fork 4, with U3).** Deliverables: `StopMonitor`; synthetic test environments where a proxy reward is hackable (planted), proving the monitor stops before held-out collapse (control that can FAIL: a monitor that never stops, and one that always stops); thresholds specified in an amendment before any real run. Depends: harness `stop` role (I-A, interface text suffices).
- **U3 Graded preference tuning with the variance fix (same fork as U2).** Deliverables: `PreferenceUpdater` implementing the design's section 7 (graded reward, rank pairs with margin, variance filtering, group >= 16, KL/weight-delta gate), tested on a toy policy where the old binary reward gives zero-variance groups and the new one learns; diagnostics logged. Depends: nothing but the interface text.
### Track E — evaluation (already launched)
- **E Stage-0 baselines + amendment (existing fork `a0e37…`).** Restricted to: pre-registration amendment (stop role, MDE rule, controls, P(pass)), timing probes, ALL baselines at the pilot budget with >= 5 seeds on EC2, MDE. It does NOT build the hybrid; the hybrid is assembled at milestone M3 from tracks I and U. (The coordinator has told it so.)

## 4. Schedule (waves; owners poll themselves)
- **Wave 0 (now, 0-30 min):** I-A commits `contracts.py`; E commits the amendment; all others read the design + this plan.
- **Wave 1 (parallel, ~2-4 h wall clock):** I-A, I-B, U1, U2+U3, E run concurrently on separate EC2 instances/prefixes; no shared writers; each commits tests + code under `allatom_paper/<stream>/`.
- **M1 integration smoke (coordinator, ~1 h):** toy generator + automaton + retriever + preference updater + harness; planted-optimum oracle found; all controls behave (shuffled reward = random; copy-seed plateau). Gate: M1 must pass before any GPU hybrid run.
- **M2 baselines done (E):** curves + MDE + P(pass) committed.
- **M3 stage-1 hybrid pilot (one integration fork, ~3-5 h):** ChemFM-1B + LoRA with U1 mask, I-B retrieval, U3 updates, U2 monitor; B = 1,000, >= 5 seeds; ablations no-rules, no-feedback first. **Stop rule: if the hybrid's AUC-top-10 point estimate (train and held-out) is not above the best baseline at the pilot budget, stop, report GO / NO-GO-detectable / INCONCLUSIVE per interval vs margin.**
- **M4 ablations and U4/U5 (only if M3 passes), M5 stage 2 (needs owner go-ahead and the cost estimate), M6 arm G and audits, M7 manuscript.**

## 5. Budget (stages 0-1 hard cap USD 14, estimates)
| item | cap |
|---|---|
| I-A (CPU tests, smoke) | 1.5 |
| I-B (CPU, one GPU embedding smoke) | 1.0 |
| U1 (CPU tests + 200-step LoRA smoke) | 2.0 |
| U2+U3 (CPU toy + one short LoRA/DPO smoke) | 2.0 |
| E (baselines, probes) | 4.0 |
| M3 reserve | 3.5 |
Total 14.0. Anything beyond (stage 2: USD 45-60; stage 3: USD 25-30) needs the owner's go-ahead with the measured estimate.

## 6. Risks and mitigations
- *Interface drift between parallel streams:* contracts frozen in wave 0; any change by amendment commit + message to affected owners.
- *Mask makes ChemFM's distribution degenerate:* measure KL to the unmasked model and diversity; the fine-tune-under-mask step exists for this; ablation keeps post-hoc filtering.
- *Held-out leakage (pretraining overlap, arm G):* post-cutoff documents only or label contaminated; independence checks in the harness.
- *Reward hacking of train verifiers:* U2 monitor + held-out evaluation; report both curves.
- *Underpowered result:* MDE first; if MDE > 2 x margin the outcome is INCONCLUSIVE by construction and the plan says so before running.
- *Spot reclaim / idle instances:* resumable jobs, wall-clock caps, per-prefix single writer, cost log, coordinator heartbeat.
- *Odds:* design-doc judgement: primary gate ~20%, arm G ~30-35%, publishable result including negatives high. We proceed because the evaluation is valid and cheap to stop.
