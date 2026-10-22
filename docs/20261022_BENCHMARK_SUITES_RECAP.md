# Benchmark Suites Recap — RealBio & DrugDev

**Date:** 2026-10-22
**Scope:** the two sibling benchmark suites and their current, measured status. Numbers below are
pulled from the live files (leaderboard, dataset line-counts, MANIFEST), not estimates.

---

## 1. RealBio Benchmark (`evaluation/datasets/public_export/`)

**Purpose:** objective, leakage-controlled measurement of BioMate's core bioinformatics-agent
capabilities across LLMs, with a neutralized public export (`build_export.py`). Driven by
`run_all.py` / `run_baseline.py` → `leaderboard.{csv,md}`.

### RealBio is a FIVE-dimension eval (Evaluation Framework v1), not accuracy-only
`evaluation/core/five_dimension_reporter.py` (`FiveDimensionReporter`) scores every run on:

| dim | measures | implementation | status |
|---|---|---|---|
| **D1 Performance** | accuracy score, CI, pass-rate | the task scorers → `leaderboard.{csv,md}` | surfaced in leaderboard |
| **D2 Stability** | cross-run **consistency_rate** (all N runs agree), score-variance, Cohen's κ, **flip_rate** | `stability_runner.py`, `run_stability.py`, `run_consistency_benchmark.py` (results under `results/stability`, `results/consistency_v2`) | implemented; **CLAUDE.md target ≥90%** |
| **D3 Time** | latency/query — p50/p95 | per result + per-task `*.usage.json` → **`leaderboard_5d.csv`** (`build_5d_leaderboard.py`) | **surfaced** |
| **D4 Cost** | tokens in/out per query (proxy; $ needs price map) | `*.usage.json` → **`leaderboard_5d.csv`** | **surfaced** |
| **D5 Hallucination** | grounded \| hallucinated \| unverifiable at important steps; rate + type (A/B/C/D) | `hallucination_detector.py` (LLM-judge) + `litqa2/citation_veracity.py` | implemented |

Full-5D run: `FiveDimensionReporter(..., n_stability_repeats=3, hallucination_sample_frac=0.3)`.
**D3+D4 now consolidated:** `build_5d_leaderboard.py` → `leaderboard_5d.{csv,md}` (20 models), from
the committed `*.usage.json`. It surfaces what accuracy hid — e.g. DeepSeek-v4-pro's routing 0.415
comes at **24s p50 / 1190 output-tokens per query**, and Qwen3.8-max at 32.7s / 1326, vs
Claude-Opus-5.5 at **4s / 92 tokens** and the on-prem stub at ~1s. The "thinking" open models are
slow + verbose; accuracy alone misranks them on efficiency. **D2/D5 still show `pending`** per model
(need the gated multi-run consistency + hallucination sweeps). So the headline `leaderboard.csv` =
D1; `leaderboard_5d.csv` = D3/D4; D2/D5 pending.

**RealBio-NATIVE D1 (Performance/accuracy) tasks (general bioinformatics-agent capability) = 610 items:**

| task | items | what it measures |
|---|---|---|
| cross_domain_routing | 200 | intent → correct workflow |
| param_prefill | 170 | context → workflow params (F1) |
| protocol_thresholds (QC) | 100 | QC-gate threshold reasoning |
| autofix | 100 | error → corrected params |
| workflow_generation | 40 | generate a valid workflow |

> **The shared leaderboard also has 3 DrugDev columns** — `pbpk_2fold` (15), `boin_mtd` (20),
> `dd_spearman` / drug_discovery_e2e (15) = 50 items. **These are DrugDev benchmarks (B3/B4/B2),
> only *surfaced* through the RealBio public export — not RealBio capabilities.** They are described
> in §2. (8 leaderboard columns = 610 RealBio-native + 50 DrugDev = 660 total; the "660" figure
> mixes both suites.)

**Extra RealBio-native tracks (not in the 8-col leaderboard):** accession_routing 166, litqa2 199,
intent_interpretation 95, findings_probe 50, task_decomposition 29 (+ bioc_method_selection,
nextflow_coding with their own runners).

**Current leaderboard (`leaderboard.csv`, verbatim)** — columns 1–5 are RealBio-native;
**`pbpk` / `boin` / `dd` (last 3) are DrugDev**, shown here only because both suites publish to the
same export:

| model | routing | autofix | param_F1 | wf_gen | QC | pbpk◆ | boin◆ | dd◆ |
|---|---|---|---|---|---|---|---|---|
| Claude Opus 5 | 0.615 | 0.870 | 0.757 | 0.500 | 0.330 | 0.133 | 0.444 | 0.700 |
| Gemini 3.1 Pro | 0.580 | 0.880 | 0.693 | 0.500 | 0.630 | 0.000 | 0.278 | 0.700 |
| GPT-5.6 | 0.530 | 0.860 | 0.671 | 0.500 | 0.460 | 0.200 | 0.500 | 0.700 |
| Qwen3.8-Max | 0.345 | 0.860 | 0.692 | 0.500 | 0.460 | 0.000 | 0.111 | 0.700 |
| GLM-5.2 | 0.400 | 0.830 | 0.641 | 0.500 | 0.440 | 0.000 | 0.111 | 0.700 |
| Kimi K3 | 0.450 | 0.770 | 0.628 | 0.450 | 0.360 | 0.000 | 0.167 | 0.700 |
| DeepSeek V4 | 0.415 | 0.800 | 0.621 | 0.500 | 0.420 | 0.067 | 0.167 | 0.667 |
| **BioMate (engine-free, C2)** | **0.965** | — | — | — | — | 0.200 | — | — |
| Biomni (A1 scaffold) | 0.950 | 0.950 | 0.708 | 0.500 | 0.500 | 0.000 | 0.500 | 1.0 (n=4) |

**Reads:** bare frontier LLMs sit at routing ~0.35–0.62; **BioMate's harness lifts routing to
0.965** (the LLM+harness dividend — the single biggest signal, on a RealBio-native task).
On the DrugDev columns (◆): PBPK is near-floor for all LLMs (~0.0–0.2) — a known hard task where
BioMate ties, not leads; `dd_spearman` is flat/saturated (read with caution). `workflow_gen`
(RealBio-native) is likewise flat.

**Roster** (`models.yaml`): frontier (Claude Opus 5.5, GPT-6.1, Gemini 3.8-flash/3.1-pro) + open
(GLM-5.3-prime, Kimi-k3, Qwen3-max, **DeepSeek v4-pro + v4.1-flash**, GLM-5.2, Gemma) + BioMate
on-prem + Biomni. Bare-vs-harness is a first-class axis (`HARNESS_DIVIDEND_SCALING`).

**Caveats (2026-10 audits):** `decomposition_v2` is a same-generator leak — cite `decomposition_real`
(≈0.016 base), never the retracted 0.73. DeepSeek roster slugs were stale (fixed; small model not yet
on the leaderboard — `20261021_DEEPSEEK_COVERAGE_AUDIT.md`).

**Open-model coverage (Kimi / GLM audit, 2026-10-22):**
- **Kimi K3** — fully compared: D1 leaderboard (routing 0.450 / param 0.628 / autofix 0.770 …), full
  9-task sweep, in `leaderboard_5d` (17s p50 / 1272 out-tok). Roster-verified.
- **GLM** — the leaderboard carried only the *older* GLM-5.2. **Added GLM-5.3-prime** (flagship) this
  session from its committed 5 RealBio-native tasks → routing 0.375 / autofix 0.820 / param 0.651 /
  wf_gen 0.500 / QC 0.550; **boin/pbpk/dd blank (pending the gated DrugDev sweep)**. Note: the newer
  flagship is NOT uniformly better than 5.2 (routing 0.375<0.400; QC 0.550>0.440) — a "newer-gen ≠
  better" signal consistent with the size-sweep findings.

---

## 2. DrugDev Benchmark (`evaluation/datasets/drugdev_export/` + decision suite)

**Purpose:** sibling suite for drug-development capability. Redesigned 2026-10-21 from tool-routing
to **context-rich DECISION tasks** graded against real measured data (see
`20261021_DRUGDEV_BENCHMARK_PRACTICAL_REDESIGN.md`).

**Practical decision suite — 30 tasks / 9 archetypes, one adapter (`DecisionBenchmarkAdapter`),
one runner (`run_decision_benchmark.py`), 6 scorers:**

| code | archetype | tasks | scorer | ground truth |
|---|---|---|---|---|
| D1 | leadopt_triage | 3 | decision | measured ADMET (ChEMBL/FDA) |
| D2 | fep_selection | 2 | decision | experimental ΔΔG (Merck) |
| D3 | dose_decision (MTD) | 3 | mtd | BOIN op-characteristics |
| F1/G | dose_projection | 3 | numeric | FDA MRSD formula / allometry |
| F2 | tissue_exposure | 3 | categorical | Kp,uu / organ partition *(provisional)* |
| F3 | dose_schedule | 3 | categorical | PK/PD class |
| F4 | special_population | 4 | categorical | FDA label adjustments *(provisional)* |
| P | process_knowledge | 6 | categorical+set | FDA/ICH lifecycle |
| W | workflow_chain | 3 | chain | reference stage DAG + gates |

Scorers: `decision_scorer.{score_decision, score_categorical_decision, score_set_decision,
score_numeric_decision}` + `boin_scorer.score_mtd_decision` + `chain_scorer.score_chain`. Answers
hidden from prompts; self-tests green (15/15, 5/5, adapter 34/34).

**Tool/stage benchmarks (B/N series):**

| code | name | status |
|---|---|---|
| B1 | admet (20) | exported |
| B2 | docking | public in RealBio (drug_discovery_e2e) |
| B3 | pbpk | public in RealBio |
| B4 | boin | public in RealBio |
| B5 | target_structure (10) | exported |
| N1 | rbfe (8 series / 264 ligands, real Merck ΔΔG) | gold + scorer + adapter built; **Batch runner pending** |
| N2–N9 | qsar / generation / retrosynthesis / stability / novelty-FTO / ind-narrative / **pipeline-e2e (flagship)** / cross-stage | planned |
| T2a/b, T3a/b | target-id / perturbation / retrieval / knowledge | planned (compete+cite external) |

**Benchmark→training loop:** the decision suite exports SFT + GRPO gold (`build_decision_sft.py` +
`decision_reward.py`) with a **disjoint, leak-guarded** train/eval split (22 train / 8 eval);
`learn_decision` vs `route_not_compute` policy tags.

**Composer evals (this session):** `composer_eval` / `composer_eval_curated` /
`dag_resolution_coverage` / `retype_dryrun` — offline tools that diagnosed the multi-task composer
(see `20261021_DAG_RESOLUTION_COVERAGE_RESULT.md`).

---

## 3. Cross-cutting status & honesty notes
- **Built + self-tested offline:** RealBio sweep machinery + 8-task leaderboard; DrugDev decision
  suite (30 tasks), N1 RBFE (gold/scorer/adapter), the training-gold loop, composer evals.
- **Gated (live stack, not run speculatively):** N1 Batch runner, N8 pipeline-e2e flagship, the
  decision suite's L5–L6 execution grading, the model-roster sweep for new entries.
- **Provisional:** F2/F4 numeric values (textbook/class-level, web-unverified — flagged).
- **Landscape:** ~165 external drug-dev benchmarks surveyed (`20261021_DRUGDEV_BENCHMARK_LANDSCAPE_AND_SERIES.md`).
- **Recurring lesson across both suites:** measure on leakage-controlled / correct-granularity
  splits; several headline numbers collapsed under clean evals, which is itself why "performance"
  looked off (`20261021_PERFORMANCE_DIAGNOSIS.md`).
