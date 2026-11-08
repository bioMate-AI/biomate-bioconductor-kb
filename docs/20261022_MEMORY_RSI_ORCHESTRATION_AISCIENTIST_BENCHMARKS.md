# New benchmark dimensions: Memory, RSI, Orchestration, and AI-Scientist comparison

**Date:** 2026-10-22
**Scope:** Four benchmark threads requested this session, tailored to drug development and other
important tasks. Each is grounded in what already exists (audited first) so we extend/wire rather
than rebuild. Companion to `20261021_DRUGDEV_BENCHMARK_PRACTICAL_REDESIGN.md` and
`20261022_BENCHMARK_SUITES_RECAP.md`.

---

## 0. One-line status

| Thread | Pre-existing | Delivered this session | Pending (gated/next) |
|---|---|---|---|
| **Memory** | Full LongMemEval/LoCoMo/BABILong-aligned bench (20 scen, runner+adapter) | +12 drug-dev decision episodes (MB-DD1..12), 32 total | roster sweep bare-vs-harness |
| **RSI** | `autoloop_benchmark_adapter` = within-run QC convergence | `rsi_scorer.py` (3 longitudinal axes + leakage firewall) | adapter + live/GPU axes (gated) |
| **Orchestration** | decomposition_real / composer_eval / reverse_decomp / lane_arbitration (standalone) | `orchestration_benchmark/` suite manifest composing them | consolidated roster sweep |
| **AI-scientist comparison** | Biomni already a RealBio row; 3 external adapters | plan + comparator rows defined | run bioagentbench/sciagentbench; add TxAgent/FutureHouse |

---

## 1. Memory — extended, not rebuilt

BioMate already has a real memory benchmark (`evaluation/datasets/memory_benchmark/`, runner +
adapter + 5-type agentic backend `agentic_memory.py`), explicitly mapped to **LongMemEval**
(ICLR 2025), **LoCoMo** (ACL 2024), **BABILong** (2024). Its 20 scenarios test *routing* memory.

**Gap = drug-dev coverage.** Added 12 episodes (`MB-DD1..12`) for the memory failures that bite a
drug-dev **program**:

- **value carryover** — program-specific non-default values that recall can only get from memory:
  hERG gate 7.5 µM, oral-F cutoff 28%, cyno allometric exponent 0.72.
- **entity persistence** — PD-L1 macrocycle PPI target/modality; T2T-CHM13 program reference.
- **negative memory** — avoid rhodanine (PAINS); recall the BM-4471 CYP3A4-TDI failure.
- **tool correction** — GATK→DeepVariant (PacBio HiFi); docking→RBFE (lead-opt).
- **value supersession / staleness** — MTD 400→300 after a DLT; solubility 15→63 µM.
- **baseline regression** — plain ADMET still routes despite seeded episodes.

**Design rule:** every seeded value is deliberately non-guessable → a correct recall PROVES memory
(the implicit **memory-OFF ablation**). Mapped onto the existing scorer types only
(recall/correction/adversarial/baseline) → **zero adapter change, published weighting preserved**.
Supersession is encoded as `correction` (expected = new value, disqualified = stale value) so it
scores 1.0 only if the current value is given AND the stale one is suppressed. Offline oracle-vs-wrong
check: 12/12. Commit `c0001575c`.

---

## 2. RSI (recursive self-improvement) — the genuinely new axis

**Already covered:** `autoloop_benchmark_adapter.py` measures **within-run** QC convergence
(gate-pass@1, converge ≤3 iters) across ADMET/CYP-DDI/Docking/NCA-PK — "no public benchmark measures
autonomous QC convergence." That is RSI *inside one run*. Not rebuilt.

**Missing = longitudinal / cross-run self-improvement.** `evaluation/scorers/rsi_scorer.py` (commit
`b9464d77c`), modeled on STOP / ADAS / Darwin-Gödel Machine / SICA / AlphaEvolve (all Δ-over-iterations
on a held-out), with the firewall those papers — and our retracted `decomposition_v2` — lack:

- **A. `score_learning_curve`** — cross-episode success net of a **no-learning control** (nets out
  task order + noise). Composes with the memory bench: negative memory should reduce repeat failures.
- **B. `score_capability_growth`** — Δrouting-coverage from composer-generated workflows, **gated by
  executes-for-real** (`real_exec_status`). A capability that doesn't run scores 0.
- **C. `score_self_improvement`** — Δ on a clean held-out after a self-training loop
  (error-analysis → owner-bucketed gold → GRPO). **HARD-ZERO unless out-of-generator** (leakage
  firewall), ×(1−forgetting) sibling-regression guard.

`--selftest` 8/8: genuine learning high; all-from-control → 0; in-generator lift → firewall 0;
OOG lift → full; catastrophic forgetting penalized. Axis A is offline-scorable over logged
trajectories now; B and C reuse the already-gated composer / `stage_onprem_rl_run.sh` paths.

---

## 3. Orchestration — a separate benchmark (not folded into RealBio)

Decision (user, 2026-10-22): make decomposition + orchestration their **own** suite rather than
re-weight RealBio. `evaluation/datasets/orchestration_benchmark/` (MANIFEST + README) composes the
existing components — **no data duplicated**:

| Component | n | Scorer |
|---|---:|---|
| decomposition_real (OUT-OF-GENERATOR) | 68 | decomp_reward node/edge-F1 |
| composer_orchestration (executable DAG) | 9 | chain_scorer + type_satisfies |
| reverse_decomp | 300 | need_grader |
| lane_arbitration | 40 | lane arbiter |

Discipline: **decomposition_v2 is excluded** (retracted leak); bare-vs-harness for every component;
composer credit requires a type-satisfying (executable) DAG. The semantic type-handoff fix this
session lifted DAG fire 4.4%→38.2%; cross-ecosystem representation is a real remaining gap.

---

## 4. AI-scientist comparison — open science, Biomni, and others

**Already true:** Biomni is a first-class **RealBio comparator row** today
(`Biomni (A1 scaffold)`: routing 0.95, boin 0.5, pbpk 0.0) via `run_biomni_realbio.py` (Biomni as
agent-under-test, same items as `run_baseline.py`), and `biomni_eval1_adapter.py` runs BioMate on
Biomni's own Eval1. Both directions covered. Known blocker: Biomni prefill breaks on Claude ≥4.6/opus-5.

**Wired but unrun (0 results):** `bioagentbench_adapter.py`, `sciagentbench_adapter.py` — run these
to place BioMate on established agent benches.

**Add as comparators** (open-science, drug-dev-relevant):
- **TxAgent + ToolUniverse** (Zitnik, open; 211-tool therapeutics planner) — closest drug-dev
  multi-tool orchestration competitor; natural row on orchestration + drug-dev decision suites.
- **FutureHouse** open agents — PaperQA2 (literature), Robin (repurposing), Aviary env — the
  "open science" systems; relevant to the knowledge-recall / research tasks.
- **STELLA** (self-evolving biomedical agent) — the natural comparator for the **RSI** suite.
- Benchmarks to be evaluated ON (compare vs their published agent numbers): **BixBench**,
  ScienceAgentBench, BioAgentBench, LAB-Bench.

**Principle:** every comparator is scored on the **same items** (fair same-item comparison, as the
Biomni row already is), and every suite reports **bare vs +harness** so the comparison isolates the
agent/harness contribution from raw model capability.

---

## Commits this session

- `fae539458` unified GRPO reward over the whole 12,275-row corpus (decision+routing+param+autofix)
- `c0001575c` memory benchmark drug-dev episodes (MB-DD1..12)
- `b9464d77c` RSI scorer (3 longitudinal axes + leakage firewall)
- (this doc + orchestration_benchmark suite)

## Next (nothing fired without an explicit go)

1. Roster sweeps: memory (32 scen) + orchestration (417) bare-vs-harness across the LLM roster.
2. Run `bioagentbench` + `sciagentbench` (BioMate on external agent benches).
3. Add TxAgent / a FutureHouse agent / STELLA comparator rows.
4. RSI adapter + the gated live/GPU axes (composer coverage growth; error-mined GRPO lift on OOG held-out).
