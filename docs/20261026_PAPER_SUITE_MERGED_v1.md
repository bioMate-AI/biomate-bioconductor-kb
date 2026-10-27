# RealBio: an open, objectively-scored benchmark SUITE for biomedical-agent task routing, selection, and extraction — and what the knowledge layer buys

**Merged suite paper v1 (2026-10-26).** Supersedes and merges `20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md`
(A) and `20261004_PAPER_B_HARNESS_VS_LLM_DRAFT.md` (B): per the 2026-10-26 editorial ruling + the 3-LLM
committee (unanimous AGREE), the bare-vs-harness analysis is the **results section of the suite**, not a
separate paper. All numbers trace to **Results Release v1** (`20261026_RESULTS_RELEASE_v1_CLAIM_REGISTRY.md`),
scorer `score.py @ e281c1bdd`. The on-prem/platform systems story (cost/compliance + the negative fine-tuning
result) is a SEPARATE paper (D).

**Status:** draft; NOT submit-ready. Open items (committee punch-list) are listed in §7 and gate submission.

## Abstract
Agentic systems for biomedical research are usually framed as "a better model." Using an open,
deterministically-scored benchmark **suite** (RealBio) and a matched **bare-LLM vs LLM+harness** protocol
across frontier, open, and on-prem models, we find that **a candidate-context / deterministic-rule layer
substantially improves the evaluated selection, routing, and extraction tasks** — often more than model
scale. We report every result under one shared scorer with explicit conditions, publish negative results and
withdrawn artifacts, and bound the claims: this is a per-task-suite measurement, not a demonstration that
biomedical automation is model-invariant.

## 1. Contributions
1. **An open benchmark suite** (one deterministic `score.py`, fixed public items) for the general
   bioinformatics-AGENT capabilities: workflow routing (n=200), **channel routing** (the stage-1 "which
   resource" decision, n=84, 64% drug-development queries), param-prefill (n=170), autofix, and
   workflow-generation. No LLM-judge. *(Drug-development decision/prediction tasks — PBPK, BOIN, docking,
   ADMET, QSAR, FEP — are a SEPARATE sibling benchmark, DrugDev-Bench, not part of RealBio.)*
2. **A matched bare-vs-harness protocol** that isolates the candidate-context contribution on the SAME model
   snapshot, empties-aware (budget tokens past reasoning; retry; flag empties) — reported as each benchmark's
   primary result.
3. **Honest negatives + corrections**: two regressed fine-tuning attempts, a semantic-vs-string scorer
   correction, and a held-out independence audit of the deterministic components.

## 2. The suite (what each benchmark measures)
- **Workflow routing** — given a pipeline request, pick the correct workflow (63-label catalog, 13 domains).
- **Channel routing** — the upstream decision: route to workflow / tool-search / database-lookup /
  literature / code-execution / knowledge-answer / dataset-discovery (7 channels ≡ production `ActionCategories`).
- **param-prefill** — extract workflow parameters from a request (restraint-rewarded; `{}` can be correct).
- **autofix** — map a failed-run error to the correct fix category.
- **workflow-generation** — produce the right workflow category / key tools for a request.

*(Drug-development decision tasks (PBPK, BOIN, docking, ADMET, QSAR, FEP) live in the separate sibling
benchmark DrugDev-Bench (`../drugdev_export/`), a distinct workstream — not scored here.)*

## 3. Primary results — matched bare vs +harness (Release v1; scorer e281c1bdd)
### 3.1 Workflow routing (n=200, +harness = described candidate menu)
Representative rows (full table in Release v1 §1): Opus-5 0.615→0.990, GPT-6.1-sol-pro 0.590→0.985, Gemini-3.1
0.580→0.975, Kimi-K3 0.495→0.970, DeepSeek 0.415→0.850, **BioMate 9B (base) 0.180→0.905**, Qwen3.5-9B
0.120→0.830, Qwen2.5-7B 0.140→0.735. The harness lifts every model; the lift is largest for low-bare models.
*(Honest framing: "lower-bare-score models show larger absolute gains on these bounded-accuracy tasks" — a
ceiling/headroom pattern, not asserted as an inverse-scaling mechanism.)*

### 3.2 Channel routing (n=84; 7-model roster, bare→+harness)
The dividend holds across every model with the same inverse pattern (small on-prem model gains most):
Qwen3.5-9B 0.750→0.964 (+0.214), GLM-5.2 0.821→1.000 (+0.179), DeepSeek 0.833→0.976 (+0.143), Kimi 0.845→0.988
(+0.143), Gemini-3.1 0.893→0.988 (+0.095), Opus-5 0.905→1.000 (+0.095). On-prem 9B drug-dev subset 0.778→0.982.
(Per-channel: 5/7 perfect +harness; residual tool-search↔literature.)

### 3.3 param-prefill (n=170) — raw LLM vs the shipping system
The leaderboard column is the **raw** LLM (rule layer OFF). BioMate's production path (rule layer + 9B + IO
guardrail) scores **F1 0.843** vs the raw on-prem 9B's 0.703 — the public benchmark under-measures the shipping
system because it bypasses the deterministic layer. (Canonical production measurement via `run_param_prefill.py`
vs the live backend is pending.)

### 3.4 Synthesis (the former Paper-B thesis, now the suite's discussion)
Across routing, channel-routing, and param, the candidate-context / rule layer is the dominant measured lever
on these tasks; a small on-prem model **approaches** several frontier results **with** the harness
(routing 0.905 vs 0.94–0.99 — *approaches, not parity*), while two fine-tuning attempts regressed. We do not
claim model-invariance or frontier-parity; we claim the knowledge/harness layer substantially improves the
evaluated selection/extraction/routing tasks and is the higher-leverage place to invest than model weights.

## 4. Scoring & conditions (Methods)
One deterministic `score.py` (semantic: genome/bool aliases, `_`≡space, region containment) scores every
system on the same items. Conditions are defined once (Release v1 §0): **bare** (query only), **+harness
described** (query + candidate catalog with descriptions, matched same-model), **engine-free product** (full
retrieval, no LLM — a data-point, not the headline). Empties are handled by cause (truncation → re-run;
content-filter → real; valid `{}` → correct).

## 5. Independence audit (deterministic components)
Because the scorer and organism→genome rule layer were refined after examining errors, we test them on a
held-out set (authored without reusing tuned items): on new instances they generalize at **88% (15/17), zero
hallucinations**, and **abstain correctly** on uncovered organisms (pig/chicken) — not dev-set overfit
(`20261026_HELDOUT_INDEPENDENCE_AUDIT.md`). The description-fix / routing held-out LLM eval is pending.

## 6. Limitations (committee-mandated, honest)
- The engine-free product number (0.965) is a system data-point, not a model-controlled comparison.
- Some cells are flagged non-citable (gpt-5.6 names-only menu; qwen3.8-max bare 44% empty; opus-5.5
  content-filter refusals); 17/20 routing_harness cells are uniform `described`.
- "Selection" accuracy is high **conditional on retrieval**; end-to-end routing ≈ 0.80.
- param-prefill's "fill only if stated" vs the gold's organism→genome inference is a condition caveat (the
  raw-LLM column is a floor; the production rule layer does the canonical inference).
- Channel routing n=84 is a seed set, not evidence of production prevalence.

## 7. Open items before submission (gate)
(1) make matched bare-vs-harness the primary table in all figures + wire the rule layer into the param eval;
(2) the official `run_param_prefill.py` production param figure (rule layer + 9B); (3) the full-roster
channel-routing + the held-out routing LLM eval (both substantially done); (4) build the claim registry's
per-number manifest into the supplement; (5) complete autofix/workflow_gen cells for the remaining models.
Re-convene the committee before declaring submit-ready (submit-review gate). (DrugDev-Bench task-spec fixes —
e.g. the PBPK endpoint — belong to that separate benchmark, not here.)
