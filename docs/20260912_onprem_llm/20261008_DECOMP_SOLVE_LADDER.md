# Can a small on-prem LLM do BioMate's REAL decomposition? — the SOLVE size ladder

**Date:** 2026-10-08
**Author:** Yaoyun Zhang (with Claude Opus 4.8)
**Question:** At what model size does an on-prem LLM reach *usable* real-task decomposition,
graded by need-satisfaction on the REAL held-out arbiter?
**Test:** `evaluation/datasets/reverse_decomp/reverse_decomp_test_real.jsonl` — 300 REAL
queries harvested from `workflow_chains.example_queries` (the held-out arbiter; zero
capability-combo overlap with any train set).
**Grader:** `evaluation/datasets/reverse_decomp/need_grader.py` (need-satisfaction; see
`20261008_REVERSE_DECOMP_DATASET.md`).
**Models:** run as zero-shot SOLVERS via OpenRouter. No fine-tuning (this is the baseline curve).
**Harness:** `scratchpad/solve_ladder.py` (this session) — raw model output is graded by the
grader's own `_parse_plan` + `grade(detail=True)`, exactly as the grader scores.

---

## 1. What the solver is given and must produce (I/O contract)

The grader scores a plan = a JSON array of steps, each `{"sub_task", "order", "depends_on"}`.
It computes:

- **need_recall** — fraction of gold capability units satisfied by ≥1 predicted node (a node
  satisfies a unit when its `sub_task` tokens hit any accept-set member ≥0.5 OR the capability
  label ≥0.6, after stripping path/owner/version noise).
- **need_precision** — fraction of predicted nodes that map to some gold unit (punishes junk).
- **need_f1** = 0.65·recall + 0.35·precision (recall-leaning: gold is a minimal core).
- **structure** — 1.0 iff the plan's parallel/sequential/mixed/single shape (from `depends_on`)
  matches the gold's shape.
- **aggregation** — if the need implies integrate/rank/select/compare, 1.0 iff the plan has a
  ≥2-dependency fan-in node or an aggregation keyword; else 1.0.
- **reward** = 0.55·need_f1 + need_recall·(0.25·structure + 0.20·aggregation), bounded [0,1].
  (structure/aggregation credit is gated by recall — a wrong-tool plan with the right shape
  cannot score high.)

**Solver prompt (interpretation of the contract).** Each model is given ONLY the biomedical
NEED (the query, which never names a tool) plus a brief statement that it is planning against a
large real bioinformatics catalog (nf-core / Bioconductor / Galaxy / GATK / Seurat-Scanpy /
docking-ADMET / PBPK / cryo-EM / structure). It is **not** told which tools answer the query —
selecting the right tools + structure IS the task. It must emit the JSON plan directly. A single
FORMAT-only example (an unrelated metagenomics shape showing parallel + fan-in) is included so
that format-following is not confounded with capability — this is applied identically to every
model, so a too-small model that still cannot emit a parseable plan reveals that as a real
parse-failure rate (itself the finding for that size). Decoding: `temperature=0`, `max_tokens=2000`,
`<think>`/markdown-fence stripped before grading. This FORMAT-example choice is the one
interpretive decision; it is held constant across the ladder so the comparison is fair.

---

## 2. The ladder (what OpenRouter actually serves)

Smallest → ≤27B, Qwen family for consistency, plus one frontier anchor from a **different**
family than the dataset's query GENERATOR (`anthropic/claude-sonnet-4.5`), so the anchor is a
clean ceiling, not a same-family echo.

| Rung | Model (OpenRouter id) | Params | Notes |
|---|---|---|---|
| 1 | `qwen/qwen3-8b` | 8B dense | smallest clean dense Qwen served |
| 2 | `qwen/qwen3-14b` | 14B dense | |
| 3 | `qwen/qwen3.8-27b` | 27B | newest-gen, at the on-prem ceiling |
| 4 | `qwen/qwen3-vl-32b-instruct` | 32B | just over ceiling — knee locator |
| — | `google/gemini-2.5-pro` | frontier | ceiling reference (≠ generator family) |

**Small-end gap (honest):** OpenRouter serves **no sub-7B Qwen** (no 0.6B/1.7B/4B dense
instruct endpoint). The ladder therefore floors at ~8B; the "0.6B → 27B" aspiration in the
program memory cannot be measured on served endpoints — the smallest measurable on-prem point
is 8B. (The 14B and 3.8-27B dense endpoints are heavily rate-limited upstream but error-free on
retry; the VL endpoints are fast.)

---

## 3. Results — real need_grader numbers (n = 300 unless noted)

_Filled incrementally as each model completes._

| Model | Params | n graded | parse-fail | mean reward | need_recall | need_prec | need_f1 | structure | aggregation | cost (USD) |
|---|---|---|---|---|---|---|---|---|---|---|
| qwen3-8b | 8B | _running_ | | | | | | | | |
| qwen/qwen3-14b | 14B | 300 | 2.3% | **0.331** | 0.357 | 0.383 | 0.366 | 0.617 | 0.933 | 0.085 |
| qwen3.8-27b | 27B | _running_ | | | | | | | | |
| qwen/qwen3-vl-32b-instruct | 32B | 300 | 0.0% | **0.363** | 0.412 | 0.399 | 0.408 | 0.553 | 0.960 | 0.033 |
| google/gemini-2.5-pro (frontier) | — | _running_ | | | | | | | | |

---

## 3.1 Deployable Qwen3.5 / 3.8 set — the ≤27B models actually served (2026-10-08)

The three **deployable (≤27B) Qwen3.5/3.8** endpoints OpenRouter serves, verified live
(`GET /v1/models/<id>/endpoints`; none 404'd): `qwen/qwen3.5-9b` (9B), `qwen/qwen3.5-27b`
(27B), `qwen/qwen3.8-27b` (27B, newest gen). Only **two distinct sizes** on the API (9B, 27B),
so this is a 2-point size comparison + the 3.8-27B vs 3.5-27B same-size cross-check; sub-5B
sizes are not served (would need self-hosting — not faked).

**Decoding config (this block).** All three are *thinking* models. With the §1 default 2000-token
budget and reasoning on, a decomposition's reasoning alone is 2–8k tokens and the JSON array
**truncates before its closing `]`** (`finish_reason=length`) → `_parse_plan` returns `[]` → a
**parse-fail artifact, not a capability signal** (confirmed: qwen3.8-27b on the same item parses
0 steps at 2000 tokens but 9 steps at 10000). Raising the budget fixes correctness but costs
~$0.016/item for the 27B models (8.5k completion tokens), which would exceed the available
credit over 900 solver calls; and `{"reasoning":{"max_tokens":N}}` is **not honored** by
qwen3.5-27b (ran 17k reasoning chars regardless). The only reliable, uniform, budget-safe fix is
**reasoning disabled** (`{"reasoning":{"enabled":false}}`, `SOLVE_MAX_TOKENS=2500`), applied
identically to all three. Arrays then always close (parse-fail ≈0), cost is ~$0.33 total, and the
within-block 9B-vs-27B / 3.8-vs-3.5 comparisons are clean. **Not directly comparable** to the
reasoning-on `qwen3-*`/frontier rows in §3 — keep the blocks separate.

| Model | Params | n graded | parse-fail | **mean reward** | need_recall | need_prec | need_f1 | structure | aggregation | cost (USD) |
|---|---|---|---|---|---|---|---|---|---|---|
| qwen/qwen3.5-9b  | 9B  | 300 | 3.0%  | **0.347** | 0.410 | 0.394 | 0.404 | 0.353 | 0.977 | 0.023 |
| qwen/qwen3.5-27b | 27B | 300 | 0.33% | **0.362** | 0.404 | 0.391 | 0.400 | 0.597 | 0.943 | 0.118 |
| qwen/qwen3.8-27b | 27B | 300 | 0.33% | **0.367** | 0.409 | 0.387 | 0.401 | 0.613 | 0.963 | 0.190 |

*(Real `need_grader.grade()` output on raw plans; reasoning disabled; `temperature=0`; 0 API errors
on all 900 calls. n = 300/300 for every model.)*

**Findings.**
- **Need-satisfaction is flat across size and generation (~0.40 need_f1, reward 0.35–0.37).** The
  9B, 3.5-27B and 3.8-27B are within 0.02 reward of each other, and their need_recall/precision
  are nearly identical (~0.41/~0.39). Zero-shot, thinking-off, these models recover ~40% of the
  gold capability core on real held-out needs — well above the `decomposition_real` 0.016 floor
  the need-grader was built to fix, but far from usable (target would be ≫0.6).
- **The size signal that *does* move is STRUCTURE:** the 27B models get the parallel/sequential/
  mixed shape right ~0.60 of the time vs the **9B's 0.35** — the 9B tends to emit flat
  sequential chains and misses parallel/fan-in topologies. Aggregation (fan-in on
  integrate/rank needs) is high for all (~0.94–0.98).
- **Same-size cross-check:** 3.8-27B ≈ 3.5-27B on reward (0.367 vs 0.362); the newer generation
  gives no decomposition gain here. Capability on this task is bounded by *tool-selection recall*,
  not by model size or generation — consistent with the harness-dividend result (the lift comes
  from giving the catalog, not from a bigger/newer model).

## 4. Analysis — _pending full ladder_

---

## 5. Honesty notes

- All numbers are the real `need_grader.grade()` output on raw model plans; no post-hoc repair
  of model output beyond `<think>`/fence stripping applied uniformly.
- Parse-failure rate is reported as a real result (it IS the finding for a too-small model).
- `temperature=0` → near-deterministic; one pass over 300 (no multi-sample averaging).
- Rate-limited Qwen endpoints were retried with backoff; `n graded` and `api_errors` are
  reported per model so any shortfall is explicit.
