# RealBio: an open, objectively-scored benchmark for real-world bioinformatics workflow automation — and what the knowledge layer buys

**Draft v2 — 2026-10-27.** Scope corrected: RealBio is the **bioinformatics workflow-automation** benchmark
only (workflow routing, param-prefill, autofix, workflow-generation, protocol-QC). Drug-development
decision/prediction tasks are a separate benchmark (**DrugDev-Bench**) and are **not** in this paper; the
"which-resource/channel" routing benchmark is likewise separate. The bare-vs-LLM-harness analysis is this
paper's results section (not a standalone paper). All numbers trace to **Results Release v1**
(`docs/20261026_RESULTS_RELEASE_v1_CLAIM_REGISTRY.md`), scorer `score.py @ e281c1bdd`.

**Status:** review-ready draft, NOT submit-ready — open items in §9 gate submission; re-convene the committee
and the author's final review before any upload.

> **Honesty contract.** Every reported number traces to committed `score.py` output on committed predictions.
> No number is asserted from memory; where a figure is not yet measured it is written `[TO BE MEASURED]`.
> Abstention / no-grounded-answer is scored not-correct, never counted as correct.

---

## Abstract
Benchmarks for AI agents in bioinformatics are often scored by each system's own judge on its own private task
set, making cross-system numbers non-comparable and inviting (often unintentional) self-grading. We present
**RealBio**, an open, cross-system benchmark for real-world bioinformatics **workflow automation** — the
operations a working analyst needs: route a plain-English request to the correct pipeline, fill its
parameters, repair a failed run, generate a workflow, and set protocol thresholds. RealBio uses one released
deterministic scorer (`score.py`, CC-BY-4.0) applied identically to every system — no LLM judge — over fixed,
public items. Our primary analysis is a **matched bare-vs-harness protocol**: the *same* model evaluated with
and without the candidate-workflow catalog, which isolates what the retrieval/knowledge layer contributes.
Across frontier, open-weight, and on-prem models we find that **the candidate-context (harness) layer is the
dominant lever on these selection/extraction tasks**: on workflow routing (n=200) it lifts every model, and
most for the lowest-scoring models — a small on-prem 9B model goes from 0.180 (bare) to 0.905 (+harness),
*approaching* the frontier band (0.94–0.99) without matching it. A held-out independence audit shows these
gains are not artifacts of tuning on the evaluation items. We release the open, objectively-scored protocol
and dataset; any team can run its own system on the fixed items and land on the leaderboard.

---

## 1. Introduction
Large-model "agents" now claim strong performance on biomedical tasks, but the evidence base has a structural
flaw: the benchmark, the ground truth, and the judge are frequently owned by the same group that owns the
system under test, and results are reported on private or subsetted sets. A score produced by a system's own
judge on its own private set cannot be compared across systems or independently checked.

RealBio fixes the items, publishes the ground truth, and ships one open scorer anyone runs identically on any
system. Its tasks are **real-world bioinformatics workflow automation**, not multiple-choice trivia. Critically,
RealBio's headline analysis is **not** a single-system ranking but a **matched ablation**: the same LLM scored
with and without the benchmark's candidate catalog, so a system-level result is never mis-read as a claim about
a model's raw intelligence.

**Contributions.** (1) A public, objectively-scored, 5-task benchmark of real bioinformatics workflow
automation. (2) A matched bare-vs-harness evaluation protocol that isolates the candidate-context contribution
on the same model. (3) A cross-system leaderboard over current frontier and open-weight models, an on-prem
model, and a domain agent. (4) An open scorer + dataset (CC-BY-4.0) that makes every number reproducible and
refutable. (5) A held-out independence audit showing the deterministic components and the harness dividend
generalize to unseen items.

## 2. Related work and how RealBio differs
Existing agentic-bio benchmarks (BixBench, LAB-Bench, ScienceAgentBench, BioAgentBench, BiomniBench, and
system-specific evaluations) advanced the field but commonly (a) rely on an LLM judge, (b) report on private or
subsetted items, (c) conflate "the model reasoned well" with "the product added value," and (d) are frequently
run only by the system's authors.

**Table 1 | RealBio versus existing agentic-bio benchmarks.**

| Benchmark | Open items | Open scorer | Cross-system | Objective scoring | Ablation |
|---|---|---|---|---|---|
| BixBench (FutureHouse, 2025) | Yes | Yes | Partial (2 models) | No (LLM judge) | Yes |
| LAB-Bench (FutureHouse, 2024) | Partial | Yes | Yes (8 models) | Yes (MCQ) | Partial |
| ScienceAgentBench (2024) | Partial (gated) | Yes | Yes | Partial (exec + visual LLM judge) | Yes |
| BioAgentBench (2026) | Yes | Partial (LLM-graded) | Yes | No (LLM judge) | Yes |
| BiomniBench (2026) | Partial | Partial (rubrics) | Yes | No (LLM judge) | Partial |
| **RealBio (this paper)** | **Yes** | **Yes (score.py, CC-BY-4.0)** | **Yes** | **Yes (exact/semantic match where the task admits)** | **Yes (matched bare-vs-harness)** |

Each existing benchmark opens some axes but, across the five we verified, none opens all together. We claim
this combination only for the specific benchmarks verified here, not as a universal first; several match RealBio
on individual axes. We report the systems we could run under one identical frozen-prompt protocol and invite
the rest (including closed co-scientist systems) to place their own system on the open items.

## 3. The RealBio benchmark (5 workflow-automation tasks)
| Task | What it tests | Ground truth | n |
|---|---|---|---|
| `cross_domain_routing` | plain-English request → correct workflow | curated catalog + acceptable-alternatives | 200 |
| `param_prefill` | fill a workflow's parameters from context | schema-validated expected values | 170 |
| `autofix` | classify + repair a failed run | fixed failure categories | n=100 |
| `workflow_generation` | produce the right workflow category / key tools | structural / key-tool-recall check | n=40 |
| `protocol_thresholds` | set QC/protocol thresholds (PASS/FAIL) | published protocol references | n=100 |

*(Explicitly excluded: drug-development decision tasks (PBPK, BOIN, docking, ADMET, QSAR, FEP) → DrugDev-Bench;
and resource/channel routing → the separate channel-routing benchmark.)*

## 4. Methods — scoring and conditions
**One deterministic scorer.** `score.py` (@ `e281c1bdd`, CC-BY-4.0) grades every system on the same items.
It uses **semantic** matching, not raw string identity: workflow names match with `_`≡space; parameter values
match canonical genome/boolean aliases (hg38≡GRCh38, disabled≡False) and region containment. This measures
semantic correctness; it lifts every system uniformly relative to the earlier exact-string scorer.

**Three disclosed conditions** (Results Release v1 §0):
- **bare (direct-use):** LLM + query only, **no** candidate catalog (leaderboard column `routing`).
- **+harness (described menu):** LLM + query + the retrieved candidate workflows with one-line descriptions —
  the **matched same-model** comparison and our **primary** result (column `routing_harness`).
- **engine-free product (C2):** full production retrieval, no LLM in the loop. Reported as a system data-point
  (0.965), **not** the headline — it is not a model-controlled comparison.

**Empties-aware generation.** Reasoning models can return no content when `max_tokens` is consumed by thinking
tokens; such empties are a harness artifact, handled by cause (truncation → re-run; content-filter refusal →
scored as a real failure; a correct empty `{}` on param-prefill → correct). Abstention is never credited.

## 5. Results — matched bare vs +harness
### 5.1 Workflow routing (n=200; primary result)
The harness lifts every model; the absolute gain is largest for the lowest-bare models (a ceiling/headroom
pattern — we do **not** assert an inverse-scaling *mechanism*). Selected rows (full table: Release v1 §1):

| system | bare | +harness (described) |
|---|---|---|
| Claude Opus 5 | 0.615 | 0.990 |
| GPT-6.1-sol-pro | 0.590 | 0.985 |
| Gemini 3.1 Pro | 0.580 | 0.975 |
| Kimi K3 | 0.495 | 0.970 |
| GLM-5.3-prime | 0.375 | 0.955 |
| GPT-5.6-luna | 0.355 | 0.950 |
| DeepSeek V4-pro | 0.415 | 0.850 |
| **BioMate 9B (base)** | **0.180** | **0.905** |
| Qwen3.5-9B | 0.120 | 0.830 |
| Qwen2.5-7B | 0.140 | 0.735 |
| BioMate 9B (SFT) | 0.285 | 0.810 |
| Biomni (A1 scaffold) | 0.950 | 0.950 |
| BioMate (engine-free, C2) | 0.965 | — (product retrieval, no LLM) |

The on-prem 9B base model **approaches** several frontier results under the harness (0.905 vs 0.94–0.99) and
exceeds same-class open models (Qwen3.5-9B 0.830, Qwen2.5-7B 0.735); equivalence to the frontier is **not**
established. Flagged non-citable cells: `gpt-5.6` +harness is a names-only menu (not re-run); `qwen3.8-max`
bare 0.345 has 44% empties and is not citable (Release v1 §6).

### 5.2 param-prefill — raw LLM vs the shipping system
The leaderboard `param_prefill_F1` column is the **raw** LLM (rule layer OFF). Rows labeled "BioMate 9B" are
therefore the raw on-prem model, not the shipping system. Running BioMate's production deterministic rule layer
(`_rule_based_param_inference` + `_validate_extracted_params` + IO guardrail) merged with the 9B:

| configuration | param F1 | precision | recall | source |
|---|---|---|---|---|
| raw on-prem 9B | 0.703 | 0.785 | 0.636 | `results/base/param_prefill.jsonl` |
| rule layer alone | 0.470 | 0.960 | 0.311 | `measure_production_param_rules.py` |
| **production (rule layer + 9B)** | **0.843** | 0.900 | 0.793 | `measure_production_param_rules.py` |

The public benchmark under-measures the shipping system because it bypasses the deterministic layer. The 0.843
figure is a faithful offline measurement; the official end-to-end figure against the live backend is
`[TO BE MEASURED]` (`run_param_prefill.py`).

### 5.3 Other tasks (reported, no selective highlighting)
From `leaderboard.csv` (scorer `e281c1bdd`): autofix (e.g. Opus-5 0.870, Gemini 0.880, BioMate 9B base 0.870,
Biomni 0.950); protocol_QC (e.g. Gemini 0.630, GLM-5.3-prime 0.550, GPT-5.6 0.460, Opus-5 0.330, BioMate 9B
base 0.430). **workflow_generation is near-uniformly 0.500 across systems** — this warrants investigation of
score granularity / the structural check before any capability interpretation (`[TO BE INVESTIGATED]`), and we
do not interpret it as "the task is easy/solved." Several open models have blank autofix/workflow_gen/protocol
cells (not yet run): `[TO BE MEASURED]` for Qwen3.5-27B, Qwen3.5-9B, Qwen2.5-7B.

### 5.4 Synthesis
Across routing and param, the candidate-context / rule layer is the dominant measured lever on these
selection/extraction tasks; a small on-prem model + harness **approaches** frontier results on routing, while
supervised fine-tuning of the small model did **not** help (the SFT adapter regressed: routing +harness 0.810
vs the base 0.905; §7). The honest line is "the knowledge/harness layer substantially improves the evaluated
tasks and is the higher-leverage place to invest than model weights," **not** "model-invariant," "frontier
parity," or "selection solved."

## 6. Independence audit
Because the semantic scorer and the organism→genome rule layer were refined after examining errors on the
original items, we test them on a fresh held-out set authored without reusing any tuned item
(`heldout_independence/`; `docs/20261026_HELDOUT_INDEPENDENCE_AUDIT.md`).

- **Deterministic components (no LLM):** on held-out items the rule layer + semantic scorer generalize at
  **88% (15/17), zero hallucinations** — assembly aliases 3/3; organism→genome / strandedness-kit / boolean
  11/12; IO guardrail 0 must_not_fill violations — and **abstain correctly** (no hallucination) on
  out-of-coverage organisms (pig, chicken).
- **Harness dividend (LLM, correct full-catalog conditions):** reproduces on held-out queries with the same
  inverse pattern — qwen3.5-9b 0.133→0.933 (+0.800), gemini-3.1-pro 0.667→1.000 (+0.333), opus-5 0.800→0.933
  (+0.133). (A first held-out run was mis-specified — a small menu made bare trivially easy; recorded as our
  error and corrected.)

The gains are therefore not dev-set overfit.

## 7. Limitations (consolidated)
- **Author conflict:** the scorer is open and deterministic (enabling independent audit), but the authors also
  built the benchmark, the scorer, and one evaluated system — we claim auditability, **not** "fairness by
  construction."
- **bare ≠ deployment.** The bare condition is "LLM without the candidate catalog," not "how LLMs are deployed"
  (deployment usually includes retrieval). It is the control that isolates the harness, nothing more.
- **Not parity.** The on-prem model *approaches* some frontier results under the harness; 0.905 vs 0.94–0.99 is
  not parity evidence.
- **Dividend framing.** Lower-bare models show larger absolute gains on bounded-accuracy tasks; ceiling/headroom
  effects can produce this without an inverse-scaling mechanism.
- **Selection is conditional.** Routing accuracy is high **conditional on successful retrieval**; end-to-end ≈
  0.80.
- **param condition:** "fill only if stated" vs the gold's organism→genome inference — the raw-LLM column is a
  floor; the production rule layer does the canonical inference.
- **Fine-tuning:** supervised fine-tuning of the small model did not help (regressed); we claim no model win.
- **Provenance:** the 6 re-run routing_harness cells are OpenRouter-served while the already-`described` cells
  came from their own harness — uniform *condition*, differing *serving provenance* (a secondary caveat).
- `workflow_generation` ≈ 0.500 is unexplained and not interpreted as capability.

## 8. Discussion
RealBio's value is the open, deterministic, matched-ablation protocol: it lets a reader see, per task and per
model, exactly what the knowledge layer buys. The consistent finding is that for bioinformatics **workflow
selection and extraction**, the retrieval/rule layer — not model scale — carries the performance, which has a
practical corollary: a small, privately-deployable model behind a good harness is a cost/compliance path that
*approaches* (does not match) frontier agents on these tasks. Whether this holds beyond selection/extraction is
open. We release everything so the claim is refutable.

## 9. Open items before submission (gate)
(1) make the matched bare-vs-harness tables the primary figures; wire the production rule layer into the
param eval harness and report the official `run_param_prefill.py` production param figure `[TO BE MEASURED]`;
(2) state n for autofix / workflow_generation / protocol_thresholds and fill the blank model cells
`[TO BE MEASURED]`; (3) **investigate the near-uniform workflow_generation 0.500** `[TO BE INVESTIGATED]`;
(4) complete the full-roster held-out routing eval (3 models done); (5) build the claim-registry per-number
manifest into the supplement; (6) assemble figures (routing bare→+harness dumbbell plot; dividend-vs-bare
scatter). Re-convene the committee and the author's final review before any upload (submit-review gate).

---
### Appendix: `[TO BE MEASURED]` / `[TO BE INVESTIGATED]` gaps
- Official production param_prefill F1 via `run_param_prefill.py` vs the live backend (offline approx = 0.843).
- n for autofix (100), workflow_generation (40), protocol_thresholds (100) — RESOLVED from the task data.jsonl files (2026-10-27).
- Blank leaderboard cells: autofix/workflow_gen/protocol for Qwen3.5-27B, Qwen3.5-9B, Qwen2.5-7B.
- Cause of the near-uniform `workflow_generation` = 0.500 (score granularity / structural check).
- Full-roster held-out routing LLM eval (only 3 models measured).
