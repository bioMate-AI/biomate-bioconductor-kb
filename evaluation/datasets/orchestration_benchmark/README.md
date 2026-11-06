# Orchestration Benchmark

A **standalone** benchmark for multi-task **decomposition**, workflow-pattern **orchestration**, and lane **arbitration** — the agent capabilities RealBio's routing/param tasks do not measure. Kept separate from RealBio (per decision 2026-10-22) rather than folded into its MANIFEST, so RealBio's published-baseline weighting (LongMemEval-style A/B/C/T/S/X and the 9-task leaderboard) stays comparable.

It **composes existing component datasets with their existing scorers** — no data is duplicated. See `MANIFEST.json` for the canonical definition.

## Components (n = 417)

| Component | n | What it measures | Scorer |
|---|---:|---|---|
| `decomposition_real` | 68 | multi-step request → correct sub-task nodes + dependency edges (**out-of-generator**) | `decomp_reward` node-F1 + edge-F1 + catalog validity |
| `composer_orchestration` | 9 | multi-stage pipeline → **executable** DAG (per-stage workflow + semantic type-handoff) | `chain_scorer.score_chain` + `decomposed_dag.type_satisfies` |
| `reverse_decomp` | 300 | executed plan → originating research intent (inverse) | `need_grader` |
| `lane_arbitration` | 40 | ambiguous request → correct execution lane | lane arbiter exact match |

## Discipline (non-negotiable)

1. **Leakage firewall.** Decomposition is scored **only** on `decomposition_real` (out-of-generator). `decomposition_v2` is same-generator, was retracted (reported 0.73 vs real ≈0.016), and is **excluded** here — never score it in this suite.
2. **Bare vs +harness.** Report model-only and retrieval/catalog-assisted for every component, as RealBio does, so the harness dividend is visible (the inverse-scaling pattern: small models gain most).
3. **Execution grounding.** `composer_orchestration` credit requires the resolved DAG to type-satisfy (executable), not merely be proposed. The semantic type-handoff fix this session lifted DAG fire 4.4%→38.2%; cross-ecosystem representations (e.g. `counts_matrix` vs `ExpressionSet`) remain a real gap, not a scoring artifact.

## Comparators

Score the same items for every system (like RealBio): BioMate on-prem 9B (base / sft_gold) ± harness; frontier LLMs bare + harness; **Biomni (A1)** — already a RealBio comparator and a natural decomposition/orchestration baseline since its planner decomposes; **TxAgent+ToolUniverse** — open therapeutics multi-tool planner (drug-dev-relevant).

## Status

Datasets + scorers exist and were exercised this session (composer fire-rate study). **Not yet run as a consolidated roster sweep** — that is the pending step (offline/semi-offline for decomposition/reverse/lane; composer execution grounding reuses the gated composer path).
