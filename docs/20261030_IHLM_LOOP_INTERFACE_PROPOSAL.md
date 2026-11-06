# IH-LM ↔ loop runner: interface proposal v1 (workstream 2 → workstream 1), 2026-10-30
Status: PROPOSAL for agreement. Based on reading `cyclic_llm/ihlm/model.py` (IHLM: score / update(mode) / uncertainty / propose_edits / fingerprint / cost; FastMemory layers K/offset/retrieval/edit) and `run_l7a.py` backends (`init_state / fit(state, idx, y, steps, seed) / predict(state, idx) / predict_std / cost_info`). No result here.

## 1. Adapter (mine): `IHLMBackend(rung, base, k_anchor)` in `loop_models.py`
- `state` = an `IHLM` instance; `fit` never mutates its input (WS1's `clone()` semantics) and returns a new state.
- `fit(state, idx, y, steps, seed)` → rows `[{smiles, label, source, target_seq: None}]` → `state.update(rows, mode="finetune_ranking", seed=seed, steps=steps)`. Requirement on IHLM: **every call writes the fast symbolic memory immediately (closed form)**; the slow neural update runs only every `slow_every` calls (default 3) with the given `steps`; one-shot control = a single `update` with `steps × rounds` on the final revealed set (existing `one_shot_matched` mechanics).
- `predict(state, idx)` → `state.score(smiles, sources=[…], components=RUNG[...])`; `predict_std` → `state.uncertainty(smiles, sources=[…])`.
- Rung switches via constructor only (`modules`, `FastMemory(layers=…)`): R0 `()`, R1 `("K",)`, R2 `("K","offset")`, R3 `+"retrieval"`, R4 `+"edit"`; same backbone weights for every rung (a rung differs by layers, not by training).
- K_phys: I pass `knowledge=lambda smiles_list: K[…]` (precomputed leak-free textbook K_phys, source-standardised; keyed by SMILES) — no kb_audit mining inside IHLM for the replay.
**Requested changes to IHLM (WS1):** (a) `score(..., sources=None)` — offsets are per source and currently only `uncertainty/propose_edits` take `source`; (b) `uncertainty(..., sources=...)` accepting a list and returning an array; (c) `update(..., steps=…)` honoured by the slow update; (d) a `rows[i]["anchor"]` flag is NOT needed — offsets use every revealed row of the source (shrunk, λ=3) — but `FastMemory.offsets` must expose the per-source estimate and its n for the planted-offset control; (e) `fingerprint()` to include the fast-memory digest (already `digest()`).

## 2. Anchor-reveal step (mine, in the runner)
- For R2–R4 **and for every comparator in the ladder comparison** (equal information): `init' = init + anchors`, where anchors = k ∈ {3, 5, 10} seeded peptides per source with ≥ 20 peptides, drawn from that source's peptides that are in none of E / E_s / E_f. Anchors are REVEALED (labels given) and counted in the label budget; in regime L, held-out labs get their k anchors from their non-evaluation peptides (this is exactly the "new lab with a few measured compounds" use case); training labs' anchors come from the training pool.
- Arms record `n_anchor`; the budget rule in the claim is "same labels", so R0/R1/comparators see the anchors as ordinary labelled examples.

## 3. Loop protocol (runner), IH-LM as loop components
Per round: (1) `predict` (+ `predict_std`) over the seeded candidate subset; (2) acquisition hook `acquire(scores, std, ctx)` — default greedy top-50; `ucb` = mean + κ·std (κ from the T2 design); when T2's `acquisition/acq.py` (`prov`: diversity + per-source/flat caps + early knowledge prior) lands, it is imported behind the same hook, with the pre-registered T2 configuration, not re-tuned here; (3) reveal labels; (4) `fit` = fast-memory write every round, slow update on schedule; T1's fusion schedule (reliability-weighted F2, n0 policy) replaces the plain w = n0/(n0+n) of M1 only through a registered flag and only after T1's own pre-registered result.
Logged per round: picks, scores, std, `fingerprint()`, fast-memory digest, `cost()` (params, tokens, FLOPs, GPU-seconds) — the same 13-dimension logging.

## 4. Staged pretraining (agree with WS1)
S0 atom-level corpus (ChEMBL, ≥ 0.9-Tanimoto neighbours of CycPeptMPDB removed: clean) → S1 peptide-enriched corpus **excluding every CycPeptMPDB structure** (replay labels and structures stay out of pretraining in all regimes; otherwise regime L would be contaminated by the held-out labs' structures) → loop. Any checkpoint that saw CycPeptMPDB (e.g. HELM-BERT, v4) is flagged and reported only on the contamination-controlled subset. Backbone identical across rungs.

## 5. Planted-signal controls per rung (mine, written before any IH-LM run; run on a CPU-sized IHLM)
R1 planted K channel recovered (already in my tests for the fusion mechanics); R2 planted per-lab additive offsets recovered with k=5 anchors (error < 0.15 SD) and not by R0/R1; R3 planted analog-series effect improves R3 over R2; R4 planted +Δ for N-methyl addition recovered, flip leaves the analog label unchanged (zero prior); shuffled-label control per rung (global draw) must not improve.

## 6. Open points for WS1
Is `score(... components=…)` the right place for rung switching, or constructor-only? Does `update` support `mode="one_shot_matched"` with `rounds=`? Will the PeptideCLM-2 re-implementation stay paused (agreed: external comparator, later)?
