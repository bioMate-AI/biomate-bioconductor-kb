# The knowledge layer, not the model, carries biomedical workflow automation: a task-split analysis

**Target venue:** NeurIPS Datasets & Benchmarks (analysis track) / *Bioinformatics* / PLOS Comp Biol — the analysis companion to the RealBio benchmark paper (`docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md`).
**Status:** draft 2026-10-04. Every number traces to committed `score.py` output on committed predictions (honesty contract, below).

## Authors
Yaoyun Zhang¹ (BioMate AI), et al. *(author list per the RealBio/flagship papers)*

---

## Abstract
Agentic systems for biomedical research are usually framed as "a better model." We show, across a
production bioinformatics platform (BioMate) and multiple frontier/open/on-prem LLMs, that **the dominant
lever is the knowledge/retrieval layer, not model scale** — and we make the claim falsifiable with a
**task-split**: a task is carried by the harness when it reduces to selection-from-retrieval, a deterministic
rule, or a cheap verifier; otherwise it is LLM-bound. On two independent selection tasks the **knowledge
dividend scales inversely with model strength**: supplying grounded candidate context lifts workflow routing
for a small on-prem 9B by **+63pp** (catalog) / **+20pp** (descriptions) but frontier models by far less, and
lifts fine-grained Bioconductor *method* selection for the 9B by **+15pp (0.80→0.95)** while frontier models
are already near-ceiling (≈0 dividend). A small on-prem model **plus** the knowledge layer **matches
frontier** (9B+KB 0.95 vs frontier 0.975–1.0; 9B+catalog routing 0.92 vs 0.96), and the knowledge layer
additionally drives the small model's *scientifically invalid* method choices (e.g. over-representation
analysis on a ranked statistic) **to zero** — an accuracy *and* a correctness/safety result. We further
decompose the production path into retrieval and selection: live retrieval surfaces the correct method in
the top-8 for 82.5% of cases but ranks it first only ~0.4; a knowledge-grounded selection step over the
retrieved set recovers end-to-end top-1 to **0.80** (0.97 conditional on retrieval), so **selection is
essentially solved and the remaining ceiling is retrieval recall, not the LLM**. The one capability we find
genuinely model-bound — multi-task decomposition / dependency-graph orchestration — we flag as an open
problem and explicitly decline to over-claim (our current metric is inadequate; see §6). The practical
consequence: an on-prem, cost/compliance deployment is viable because the knowledge layer, not a frontier
model, carries the system.

> **Honesty contract.** Every reported number comes from committed `score.py` on committed
> `predictions.jsonl`; none is asserted from memory. Where a metric is inadequate or a comparison is
> confounded, we say so and decline the claim (notably task_decomposition, §6). RealBio's self-grading
> disclosure (companion paper §4/§6) applies to the product rows.

---

## 1. The task-split hypothesis
We classify each automation task by what suffices to solve it:
- **(S) selection-from-retrieval** — the answer is one of a retrievable candidate set (routing, method selection);
- **(R) deterministic rule** — unit conversion, alias normalization, boolean flag mapping, schema validation;
- **(V) cheap verifier / pass@k** — an executable or programmatic check exists.
A task in S∪R∪V is **harness-carried** (model-invariant given the harness); otherwise it is **LLM-bound**
(open-ended generation with no retrievable answer and no cheap verifier). The hypothesis: most biomedical
"agent" tasks are harness-carried, and the harness — curated executable catalog, retrieval, QC gates,
rules — is the lever. We test it on selection tasks (§3–5) and identify the LLM-bound residual (§6).

## 2. Setup
- **Models:** base Qwen3.5-9B (the on-prem target; the Insilico L-Qwen winner base — cf. LongevityBench
  *Cell* 2026, which shows compact 0.6–9B domain LLMs matching frontier), plus Claude Opus-5, GPT-5.6,
  Gemini-3.1-pro, DeepSeek-V4-pro via OpenRouter.
- **Conditions:** *bare* (model's own knowledge), *+KB* (candidates annotated with grounded descriptions +
  input types from the BioMate knowledge base), *full-harness* (live product retrieval over the 4,209-wf
  catalog), *composite* (retrieve → KB-grounded selection).
- **Scoring:** single shared open scorers; top-1 accuracy, invalid-regime failure rate, retrieval@1/recall@8.

## 3. Workflow routing (RealBio cross_domain_routing, n=200)
The bare→+catalog dividend is **+63.5pp for the 9B (0.18→0.815)** vs **+34.5pp for Opus (0.615→0.960)**.
Localizing the residual gap: it is 100% selection-miss (gold always in the candidate menu); the fix is a
**harness-context** change — show the model each candidate's description, not the bare name (the discriminating
fact often lives past the truncation window). This lifts the 9B **0.68→0.885→0.915** (widened window) and is
**paraphrase-robust (0.920)** — semantic, not lexical echo (controls: paraphrase + 26-workflow recovery
breadth; no benchmark-fitted rules). Shipped to production (`UnifiedWorkflowSearch` desc 120→240).

## 4. Fine-grained Bioconductor method selection (new benchmark, n=40)
We built a context-based **method**-selection benchmark (confusable Bioconductor siblings; design-validity
gate drops pairs whose correct choice isn't predictable from observable context, e.g. DESeq2-vs-edgeR).
Four arms:

| arm | 9B | frontier | note |
|---|---:|---:|---|
| bare (names) | 0.80 | ~1.0 | frontier already knows the methods |
| +KB (descriptions) | **0.95 (+15pp)** | ≈0 dividend | invalid-regime 0.125→**0** |
| full-harness retrieval@1 | — | — | ~0.4; **recall@8 0.825** |
| composite (retrieve→KB-select) | — | **0.80** | conditional-select **0.97** |

The **KB dividend scales inversely with model strength** (DeepSeek +9.8pp between the two) — the §1 hypothesis.
The composite result decomposes the product: **selection is solved (0.97 given retrieval); the ceiling is
retrieval recall (0.825)**, so the lever to raise it is embeddings/coverage, not the model.

## 5. Unified result (the figure)
Plot KB dividend (pp) vs model strength for both tasks (`docs/20261004_KB_DIVIDEND_UNIFIED.md`): both series
rise monotonically as the model weakens. **A small on-prem model + the knowledge layer matches frontier**, and
the knowledge layer eliminates scientifically-invalid choices. This is the paper's central claim and the
justification for an on-prem (cost/compliance) deployment.

## 6. The LLM-bound residual: multi-task decomposition (open problem, NOT claimed)
Decomposing a multi-task request into a dependency-ordered sub-task plan (parallel/sequential/mixed) is the
one task not reducible to S/R/V. It is trained (9,717 instances) and served (agentic orchestrator). **We do
NOT report a capability number**: our current metric is a coarse 4-class structure bin that mis-scores plans
at finer-than-gold granularity (an artifact, not a result). The correct instrument is node-F1/edge-F1 against
a DB-verified dependency DAG (TaskBench-style), where each sub-task resolves to a real catalog workflow and
each edge is validated by input/output-type + EDAM-operation compatibility from the knowledge base. We frame
decomposition as an open problem and the right place for on-prem model training — pending that metric.

## 7. Discussion / limitations
- Frontier is near-ceiling on method selection → that task discriminates *weak* models; the on-prem claim is
  clean, but a "hard-for-frontier" variant needs more obscure methods.
- Routing's dividend is retrieval-based, method-selection's is in-context-description-based — both are "the
  harness supplies grounded context," labelled as such.
- n (40 method, 200 routing) and CIs reported; RealBio self-grading caveat on product rows; some golds need
  acceptable-alt encoding to firm up retrieval@1.
- Differentiation vs Biomni (*Science* 2025): Biomni executes ad-hoc sandbox code and is Q&A-heavy; our
  evaluation is production execution + knowledge-grounded selection over a curated catalog.

## Artifacts
`evaluation/datasets/bioc_method_selection/` (data+runners+scorer), `docs/20261004_CLOSE_THE_GAP_ROUTING.md`,
`docs/20261004_BIOC_SELECTION_MATRIX_RESULTS.md`, `docs/20261004_KB_DIVIDEND_UNIFIED.md`,
`docs/20261004_REALBIO_LLM_VS_HARNESS.md`. All predictions committed.
