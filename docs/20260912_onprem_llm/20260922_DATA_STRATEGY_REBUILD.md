# On-prem LLM data strategy rebuild — stop overfitting templated slivers (2026-09-22)

## Diagnosis (user-driven, verified)
The 4B was trained on ~18,600 SFT examples that are **templated slivers** of a far richer real dataset,
then "evaluated" on tiny (27–200) same-distribution slivers. Two consequences:
- **Overfitting is unmeasurable / likely** — train and eval come from the same generators; the removal
  metric was even falsified (degenerate baselines beat the model; see COMMITTEE_AUDIT_V4).
- **Massive under-exploitation of our own data.** Proof (decomposition task): templated set = 1,649;
  real capacity from the graph = **3,396 already** (2,010 intra-workflow step-DAGs + 1,385 WKG
  inter-workflow chains), with nf-core subworkflows (~2,249 files) not yet parsed → **~5–10k real**.

Data capacity in the DB (per task, real):
- routing/wfgen/accession: 4,198 workflows w/ description
- param: 3,058 workflows w/ params_schema
- decompose/composition: 3,152 step-DAGs (11,635 steps) + 2,249 subworkflows + WKG precede graph
- autofix/diagnosis: 1,719 workflows w/ real_exec_err
- tool composition: 9,656 tool_compatibility pairs
- 42 domains (for stratification)
Plus: **1,811 docs (26 MB)** and **5,987 commits (~3,075 fix/feat with rich problem→fix bodies)**.

## Strategy: build a large, NON-CIRCULAR corpus from real sources, leakage-split by family
Three sources, all **API/DB-only (no GPU)**:

1. **Maximally exploit the graph** (real gold, not templated samples)
   - decompose ← all step-DAGs + subworkflows + WKG chains (~5–10k)
   - param ← all params_schema (query→gold_params) (~3k)
   - autofix/diagnosis ← all real_exec_err (~1.7k)
   - routing/wfgen/accession ← all 4,198 workflows (~4k+)
2. **Committee-as-teacher distillation** (gpt-5.6 + gemini-3.8-flash) — run them AS BioMate's LLM on the
   real inputs; pool responses; **teacher consensus = silver gold** (breaks query-circularity; a
   single-teacher or query-derived gold does not).
3. **Mine our own hard work** — 1,811 docs + commit history → QA pairs, knowledge statements, and real
   diagnosis→fix trajectories (the highest-value, most in-domain, least circular data we have).

**Leakage control (non-negotiable):** freeze a held-out split by **workflow family / tool family /
source / time BEFORE** assembling train; dedup queries; eval families disjoint from train. Only then
does a per-task score measure generalization, not memorization.

## Per-task scale targets (train / held-out eval), all ≥200 eval
| task | current train / eval | target train | target eval (frozen, family-disjoint) |
|---|---|---|---|
| routing | 2.5k / 200 | 4k (all wf) | 300 |
| param | 1.9k / 170 | 3k (all schemas) | 300 |
| decompose | 1.6k / 29 | 5–10k (graph+subwf+WKG) | 300 |
| autofix/diagnosis | 0.2–0.5k / 100 | 1.5k (all real errors) | 250 |
| wfgen | 1.5k / 40 | 3k | 250 |
| intent | ~1k / 95 | 2k | 250 |
| protocol | 158 / 100 | 1k (assay×threshold, coherent) | 250 |
| accession | — / 27 | 1k | 250 |
| composition/removal | (eval only) | from graph | 300 |
+ committee-distillation pool layered on top for target quality; + docs/commits QA & knowledge pool.

## Execution order (API/DB-only; no GPU)
1. **Graph extraction** per task (deterministic gold at scale) — decompose pool DONE as proof
   (`build_decomp_pool.py` → `data_pool_v2/`); extend to param/autofix/routing/wfgen/accession.
2. **Committee distillation pass** over the real inputs → multi-teacher response pool + consensus gold.
3. **Docs+commits mining** → QA/knowledge/fix-trajectory pool.
4. **Leakage-split + freeze** eval (family-disjoint, ≥200/task); dedup vs train.
5. **Retrain** the 4B (and 27B) on the large real corpus; **score per-task** on the frozen eval +
   grounded metric. Only now are the numbers trustworthy.

## Status
- `build_decomp_pool.py` — proof built + run: 3,396 real decompose examples (vs 1,649), ceiling ~5–10k.
- `eval_alltasks.py` — per-task scorecard harness (8 LLM tasks) built; needs the ≥200 frozen eval sets.
- Next: fix subworkflow parser; extend graph extraction to all tasks; committee pass; docs/commit mining.
