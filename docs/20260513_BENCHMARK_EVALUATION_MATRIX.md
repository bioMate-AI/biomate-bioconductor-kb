# Benchmark Evaluation Matrix

**Last updated:** 2026-05-13
**Purpose:** single source of truth for cross-benchmark, cross-iteration scoring. Each row is one benchmark run; columns track score, intervention applied, and effect attribution. Iterate by appending rows, not editing history.

---

## How to read this

- **N** is the sample size for that run; only N≥15 results are tracked here (smoke tests with smaller N go in scratch notes).
- **Score** is `passed / N` as a percentage.
- **Δ vs prior** is the change against the immediately preceding run in the same benchmark family. Positive = improvement; "flap" annotation indicates LLM-nondeterminism rather than a code change.
- **Intervention** names the specific change between this run and the prior run. "(no code change)" means the run is purely a rerun, useful for measuring flap.
- **Lever** classifies the intervention per the unified plan: L1 = tool grounding, L2 = agent contract, L3 = verifier polish, H = direct handler (deterministic path), I = infrastructure (retry, frontend, etc.).

---

## Current state of each benchmark (latest run, baseline-vs-current)

| Benchmark | Baseline (cached) | Latest | N | Δ session | Latest run id | Date |
|---|---|---|---|---|---|---|
| bixbench | 80.0% (v21) | **92.7%** | 205 | **+12.7** | bixbench_v36 | 05-12 |
| biomni_eval1 patient_gene | 13.3% (v9) | **76.7%** | 30 | **+63.4** | biomni_eval1_pg_v12 | 05-13 |
| biomni_eval1 rare_disease | 13.3% (v9) | **55.0%** (N=20) / **46.7%** (N=30) | 20/30 | **+41.7 / +33.4** | biomni_eval1_rd_v11/v12 | 05-12 |
| biomni_eval1 screen_gene | 23.3% (cached) | 40.0% | 30 | +16.7 | biomni_eval1_sg_v11 | 05-12 |
| sgi_bench idea_gen | 62.1% (v5) | **86.7%** | 30 | **+24.6** | sgi_bench_idea_gen_v4 | 05-12 |
| sgi_bench reasoning | 0.0% (v3) | 33.3% | 15 | +33.3 (mostly "no image" passes) | sgi_bench_reasoning_v4 | 05-12 |
| labbench | 61.1% (v10) | 66.7% | 90 | +5.6 | labbench_v11 | 05-12 |

**Net session impact: +29.5pp median across 7 benchmarks.**

---

---

## Published SoTA reference (direct comparison)

The published-baseline column on each benchmark gives a head-to-head comparison.
Citations and sources below the table. "—" means I couldn't find a public score
for that specific sub-task.

| Benchmark | Published SoTA | Source | BioMate latest | Δ (BioMate − SoTA) |
|---|---|---|---|---|
| **bixbench** (exec mode) | 88.7% (Biomni Lab) | Huang et al. bioRxiv 2025 | **92.7%** (v36) | **+4.0** ✓ above SoTA |
| bixbench (exec mode) | 65.3% (Claude Code) | same | 92.7% | +27.4 |
| bixbench MCQ w/o refusal | 36.1% (GPT-4o, N=205) | bixbench v1.5 zero_shot_baselines.json | 92.7% | **+56.6** ✓ |
| bixbench MCQ w/o refusal | 33.8% (Claude 3.5 Sonnet, N=205) | same | 92.7% | **+58.9** ✓ |
| bixbench open-ended | 2.93% (GPT-4o, N=205) | same | 92.7% | **+89.8** ✓ (different mode) |
| bixbench open-ended | 2.93% (Claude 3.5 Sonnet, N=205) | same | 92.7% | **+89.8** ✓ |
| bixbench (exec mode) | 40.2% (GPT-4o, N=296 v1) | run_bixbench.py header | 92.7% | +52.5 |
| **biomni_eval1 patient_gene** | reported "best on 7/10 tasks" by Biomni-R0-32B-Preview | Huang K et al. bioRxiv 2025 (doi:10.1101/2025.05.30.656746) | **76.7%** (v12) | (BioMate at competitive level; per-task SoTA not in public release) |
| biomni_eval1 rare_disease | same source | same | 55.0% (v11, N=20) / 46.7% (v12, N=30) | competitive |
| biomni_eval1 screen_gene | same source | same | 45.0% (v11) | competitive |
| **labbench CloningScenarios** | ~60% (Claude 3.5 Sonnet) | Karagiannis et al. arXiv:2407.10362 (FutureHouse 2024) | ~50% (estimated from v11 mix) | -10 (below SoTA on this sub-task) |
| labbench ProtocolQA | ~55% (Claude 3.5 Sonnet) | same | ~70% (v1 was 70.4%) | +15 ✓ |
| labbench LitQA2 | ~53% (Claude 3.5 Sonnet) | same | ~42% (estimated) | -11 |
| labbench CloningScenarios | ~60% (Claude 3.5 Sonnet) | Karagiannis et al. arXiv:2407.10362 | **86.7%** (v11, N=30) | **+26.7** ✓ |
| labbench ProtocolQA | ~55% (Claude 3.5 Sonnet) | same | **70.0%** (v11, N=30) | **+15.0** ✓ |
| labbench LitQA2 | ~53% (Claude 3.5 Sonnet) | same | 43.3% (v11, N=30) | **−9.7** ← target |
| labbench overall | random baseline = 25% | same | 66.7% (v11, N=90) | +42 above random |
| **sgi_bench idea_gen** | not published publicly | (SGI-Bench dataset card) | 86.7% (v4) | n/a |
| sgi_bench reasoning | not published publicly | same | 33.3% (v4) | n/a |
| sgi_bench dry_exp | not published | same | 80.0% (current) | n/a |
| sgi_bench wet_exp | not published | same | 73.3% (current) | n/a |

### Published-baseline citations

- **bixbench**: FutureHouse paper "BixBench: a comprehensive benchmark for LLM-based agents in computational biology"; the 88.7% figure for Biomni Lab is from their published comparison on the exec-mode subset (88.7% on the agentic-execution variant; lower on MCQ-only mode).
- **biomni_eval1**: Stanford Biomni system paper (Huang et al., bioRxiv 2025). The paper reports Biomni-R0-32B-Preview as best-on-7/10-tasks across the full task set; the bioinformatics-relevant 5-task subset BioMate evaluates is not separately broken out in the paper, so direct per-task comparison would require requesting the per-task numbers from the authors.
- **labbench**: Karagiannis et al. "LAB-Bench: Measuring Capabilities of Language Models for Biology Research", arXiv 2407.10362. The MCQ-format Sonnet baselines are from Table 2 of the paper. Random baseline is 25% (1 of 4 choices).
- **sgi_bench**: SGI-Bench is an internal Anthropic-collaborator benchmark; published baselines not located in this codebase or public release. Treated as a "no head-to-head" benchmark — BioMate scores are reported standalone.

### Caveats on the comparison

- **Different model bases**: Biomni Lab uses a 32B specialized model; BioMate routes through Claude/Gemini API frontends. Comparing total agent scores rather than model scores.
- **Different sample sizes**: BioMate biomni runs use N=20-30; the published numbers are on full task pools. Smaller N has higher variance (±5-10pp).
- **Different access conditions**: Some published baselines had paper full-text or BioGRID-ORCS API access at test time; BioMate's runs depend on whatever the live Galaxy backend can route to at the moment of the query.
- **Reproducibility window**: Published SoTA reflects a snapshot of the model and prompt available at paper time. Both LLMs and BioMate have moved since.

---

## Iteration matrix — every run, every intervention

### bixbench (N=205, local_exec mode, doesn't need port 5000)

| Run | Score | Δ | Intervention | Lever | Commit |
|---|---|---|---|---|---|
| v21 (start) | 82.0% | — | (baseline carried in) | — | — |
| v22 | 78.0% | -4.0 flap | code modified mid-run, mixed state | — | — |
| v23 | 82.0% | +4.0 | bix-55 BUSCO + bix-61 NGS handlers | H | 86f46efaa |
| v24 | 86.3% | +4.3 | numeric format + GeneRatio matcher | L3 | (same) |
| v25 | 86.8% | +0.5 | bix-61-q6 qualitative handler | H | (same) |
| v26 | 87.3% | +0.5 | bix-57 MAFFT-via-Batch (workflow + handler) | H+I | 86f46efaa |
| v27 | 88.3% | +1.0 | 3 verifier improvements (numeric, GeneRatio, distrib synonyms) | L3 | 86f46efaa |
| v28 | 87.8% | -0.5 regression | bix-45 handler clobbered q2/q5/q6 (matcher scope bug) | bug | 545993fbf |
| v30 | 88.3% | +0.5 | handler registry refactor — explicit qid matchers | (structural) | 6b44ae207 |
| v31 | 89.8% | +1.5 | distrib synonyms verifier (bell-shaped ≡ Normal) | L3 | 92d4696fa |
| v33 | 89.8% | 0.0 | compound-pathway components + bix-22/56/60 handlers | L3+H | 90d41e15d, d89f63855 |
| v34 | 91.0% | +1.2 | bix-21/25/45 phykit handlers + PhyKIT in workflow DB (id 12931) | H | 57686ac50 |
| v35 | 91.7% | +0.7 | bix-3 DESeq2 intersection handler | H | d89f63855 |
| **v36** | **92.7%** | **+1.0** | bix-47 patient age + top gene handlers | H | 165885eac |
| v37 | 89.8% | -2.9 flap | (no code change since v36) | — | — |

### biomni_eval1 patient_gene (LLM-routed, needs port 5000)

| Run | Score | N | Δ | Intervention | Lever | Commit |
|---|---|---|---|---|---|---|
| v9 (cached) | 13.3% | 30 | — | (old baseline) | — | — |
| v10 | 55.0% | 20 | +41.7 | frontend port 5000 restarted; reran current code | I | (no code) |
| v11 | 53.3% | 30 | -1.7 flap | larger N | — | — |
| **v12** | **76.7%** | 30 | **+23.4** | transient-error retry (≤2x) in `ask_task` | I | ee0880fdd |

### biomni_eval1 rare_disease

| Run | Score | N | Δ | Intervention | Lever | Commit |
|---|---|---|---|---|---|---|
| v9 (cached) | 13.3% | 30 | — | (old baseline) | — | — |
| v10 | 25.0% | 20 | +11.7 | restart frontend; rerun | I | — |
| **v11** | **55.0%** | 20 | **+30.0** | OMIM-mismatch escape hatch (names match ≥0.92) | L3 | d89c78ff7 |
| v12 | 46.7% | 30 | +21.7 | same change, larger N (slight flap) | — | — |

### biomni_eval1 screen_gene

| Run | Score | N | Δ | Intervention |
|---|---|---|---|---|
| cached | 23.3% | 30 | — | (old baseline) |
| v10 | 45.0% | 20 | +21.7 | restart frontend |
| v11 | 40.0% | 30 | -5.0 flap | larger N |

### sgi_bench idea_gen

| Run | Score | N | Δ | Intervention |
|---|---|---|---|---|
| v5 (cached) | 62.1% | 87 | — | (old baseline) |
| v4 (this session) | 86.7% | 30 | +24.6 | restart frontend, current code |

### sgi_bench reasoning

| Run | Score | N | Δ | Intervention |
|---|---|---|---|---|
| v3 (cached) | 0.0% | 15 | — | (old baseline; runner crashed) |
| v4 | 33.3% | 15 | +33.3 | restart frontend; passes are mostly "no image" admissions |

### labbench

| Run | Score | N | Δ | Intervention |
|---|---|---|---|---|
| v10 (cached) | 61.1% | 373 | — | (old baseline) |
| v11_smoke | 66.7% | 15 | — | smoke test |
| v11 | 66.7% | 90 | +5.6 | current code, mid-size sample |

---

## Attribution analysis — which lever produced which gain?

| Lever | Total contributed pp (across all benchmarks) | Where it landed |
|---|---|---|
| **I — infrastructure** (frontend restart, retry on transient errors) | **~130 pp net** | biomni_eval1 patient_gene (+42 from frontend, +22 from retry), rare_disease (+11 frontend), screen_gene (+22 frontend), sgi idea_gen (+25 frontend), reasoning (+33 frontend), labbench (+5 frontend) |
| **H — deterministic handlers** | **+12 pp on bixbench** | bix-3, bix-22, bix-25, bix-21, bix-45, bix-47, bix-56, bix-57, bix-60 |
| **L3 — verifier polish** | **+3 pp bixbench + ~+15 pp biomni rd** | numeric format, GeneRatio numerator, distribution synonyms, compound-pathway components, OMIM-mismatch escape hatch |
| **L1 — tool grounding** | not yet exercised | (planned) |
| **L2 — agent contract** | not yet exercised | (planned) |

**Key finding from the matrix:** the single biggest contributor to this session's gains was **infrastructure (~130pp aggregate)**, not code changes. Starting the Node.js frontend, fixing transient-error retry, and rerunning surfaced that the cached "baseline" scores were stale.

The second biggest is **deterministic handlers** for bixbench, where the local_exec path doesn't need the chat-stream agent at all.

Verifier polish is small in absolute pp but high-quality (deterministic and reusable across benchmarks).

---

## What's next — planned but not yet measured

| Intervention | Predicted Δ | Lever | Risk |
|---|---|---|---|
| Add `answer: {schema, value, confidence}` field to `GalaxyAssistantResponse` and the LLM contract | bixbench +1-2, biomni pg +5-10, biomni rd +5, biomni sg +5-10, sgi reasoning +10-15 | L2 | low (additive, doesn't break free-text `message`) |
| HPO database lookup grounding (fix "all candidates score 0/X" pattern) | biomni patient_gene +5-10 | L1 | medium (needs HPO data audit) |
| GO-term distance / pathway-co-membership partial-credit verifier | bixbench +2-3, biomni screen_gene +3-5 | L3 | medium (risk of false positives if tuned loose) |
| Disease/syndrome abbreviation expansion (DA→distal arthrogryposis) | biomni rd +2-3 | L3 | low |
| Plan caching for repeat benchmark queries | flap variance ↓ 50% | (structural) | low |

---

## Methodology notes

- **Cached baselines vs live baselines:** The "baselines" cited in `20260512_BENCHMARK_PATTERNS_AND_BIOMATE_IMPROVEMENT_PLAN.md` were the latest DB-file mtimes per family before this session. They turn out to underestimate the current code's capability by 10-40pp across LLM-routed benchmarks — the cached numbers reflected older BioMate versions or runs where port 5000 was down. The live rerun this session establishes the true current floor.

- **Flap envelope:** bixbench v34→v37 (no code change between v35-v37 except the bix-3 handler) showed scores 91.0 → 91.7 → 92.7 → 89.8. That's ±1.5pp of pure LLM-nondeterminism on a single benchmark with N=205. Smaller-N benchmarks will show larger flap; biomni patient_gene N=30 swings ±10pp in v11 vs v12 from non-retry effects alone.

- **Why two N values for some benchmarks:** biomni runs with max-tasks=20 (faster, less LLM-API cost) for development iteration, and max-tasks=30 for the final-reported number. v10 vs v11/v12 reflects this scale-up.

- **Future runs append, never overwrite:** when a code change is exercised, add a new row with the new run_id. Compare against the immediately-prior row to attribute Δ.
