# Reconciliation: the RSI governance manuscript vs this session's results (2026-10-28)

Inputs: `docs/20261028_MANUSCRIPT_cyclic_peptide_closed_loop_RSI.md` + handoff (peer session), and this session's committed work (public manuscripts in `docs/20261027_PREPRINT_V1_PUBLIC/`, status `docs/20261027_PROGRAM_STATUS_VERIFIED.md`, protocols under `research/guangzhou_all_atom/`). No file of the peer session was edited.

## A. Corrections the RSI draft needs (facts checked against committed artifacts)
1. **§5.4 over-states.** It says the permeability loop was "refuted as a learning result". What is established: the POOLED top-decile outcome is confounded (557 of 711 hits, 78 %, from one source; the N-methyl rule's hits are 98.5 % from that source: `loop_retro/results/`, `PREREG_LOOP.md` L3). Whether the loop learns WITHIN sources is not yet known: the pre-registered within-source re-run (L3, 420 tasks) is still running. Wording should be "pooled outcome confounded; within-source result pending", and "N-methyl rule recovers 70-83 %" must carry that its own hits are 98.5 % one source.
2. **Abstract says "three artifacts", §5 lists four** (5.1-5.4).
3. **§5.1 mechanism.** The display-selector artifact is stated as abundance-circular; this session additionally measured FAMILY memorisation: a trivial k-mer logistic regression matches the LM on random splits for Abeta42 (0.986 vs 0.990) and hIAPP (0.698 vs 0.689) and drops under family-disjoint splits (hIAPP 0.52, FIKK13 0.42); PADI4 is the exception (0.865/0.864 vs LM 0.968, comparison not like-for-like) — `docs/20261027_SELECTOR_LEAKAGE_AUDIT.md`, `cyclic_llm/results/leakage_audit_*.json`.

## B. Additional firewall catches / pre-registered nulls from this session (not in the draft)
* Pose selector for co-folding samples: pre-registered one-shot test on 104 post-cutoff complexes, primary claim NOT supported (S2 59.6 % vs strongest baseline 60.6 %; oracle headroom +19.2 pp uncaptured): `multitarget/cyclic_complex_benchmark/PREREG.md`, `results/stageB_eval_S2.json`.
* Pipeline integrity: `parse_helm` dropped/mis-mapped non-canonical residues; impact bounded (no earlier tier changed): `docs/20261027_PARSE_HELM_NCAA_BUG.md`.
* Zero-byte sample files written by the co-folding model with exit code 0 (driver counted files, not valid files): commit 6ee3c1a65.
* Knowledge-base rule validation against measured permeability (N-methyl heuristic holds within laboratories in 7 of 8 but modest): `docs/20261027_KB_RULE_VALIDATION.md`.

## C. What the RSI draft lacks and this session supplies
A formal framework (KL tilt of a base model by knowledge, nested constraint chain with a computable knowledge-novelty frontier, hierarchical source model, GP-prior knowledge) and a measured frontier (usable-novel 0.6 % fixed scaffold -> 99.6 % pharmacophore-only; 97.3 % within the claim's own 9-mer form): `docs/20261027_PREPRINT_V1_PUBLIC/manuscript_knowledge_novelty.md`, `allatom/PREREG_KN1.md`. In progress: atom-level LM pretraining (source-grouped 4-fold design) and the simulated metal-aware engagement assay KN-2 (`allatom/PREREG_KN2.md`).

## D. Recommended topology (the open decision; the user decides)
Two papers, cross-referenced, shared artifacts defined once:
* **Paper A (method; lead):** knowledge-constrained, novelty-controlled closed-loop design (framework + all-atom LM + KN-1/KN-2 + within-source loop). This is the "own method" contribution.
* **Paper B (evidence standard; companion):** the RSI draft (verifier ladder + leakage firewall) extended with section B artifacts above; its honest status guardrails stay.
Reason: a governance-only paper carries no method result, which conflicts with the stated requirement of an own-method contribution; but the catalogue of caught artifacts is real evidence and is cheapest as a companion.
Not done: no merge of text; no edit to the peer session's files; its handoff guardrails (cross-target NULL, FEP masked, novelty unverified) are consistent with this session's measurements and are kept.
