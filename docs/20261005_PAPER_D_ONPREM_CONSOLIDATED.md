# An On-Premise Domain LLM for Bioinformatics Workflow Orchestration Is a Cost-and-Compliance Enabler, Not a Capability Win

**Paper D — consolidated on-prem manuscript (preprint-ready).**
*Status: consolidated draft, 2026-10-05. Supersedes and merges the two earlier on-prem drafts
(`docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md`, `docs/20260912_onprem_llm/MANUSCRIPT.md`) and the
fresh 2026-10-04/05 analyses. Corresponding system: BioMate (cloud + air-gapped bioinformatics
execution engine).*

**Authors:** [AUTHORS TBD] · **Affiliation:** BioMate · **Correspondence:** [TBD]

> Honesty contract. Every quantitative claim below is traced to a committed repository artifact and
> cited inline. Numbers that could not be independently recomputed from raw prediction files in this
> consolidation, and all unresolved provenance questions, are collected in **Appendix A**. Where the
> two source drafts disagreed, the resolution and its evidence are given in **Appendix B**. No
> numbers, citations, or authors are invented; author and DOI/repository fields are left as explicit
> placeholders.

---

## Abstract

Sensitive genomic and clinical data frequently cannot leave an institution's network, and cloud
inference cost is unbounded at scale — both of which motivate a **self-hosted** language model to
drive a production bioinformatics assistant. We ask the sharper question: *what, if anything, must
be trained into a local model versus supplied to it at inference?* Using BioMate — an execution
engine spanning a catalog of **4,209 workflows (1,092 with clean real-execution evidence) across ~36
domains and 12,312 tools** — and its open, objectively-scored RealBio harness, we report a single
load-bearing finding: **an on-premise domain LLM is a cost and compliance enabler, not a capability
win.** Bounded domain adaptation (QLoRA SFT on a grounded, leakage-controlled dataset) does **not**
move the end-to-end system bar: with the production harness (retrieval + candidate context), our
tuned base-Qwen3.5-9B is statistically indistinguishable from the stock base on every task (routing
0.805 vs 0.815; param-prefill F1 0.657 vs 0.664; autofix 0.85 vs 0.87). The harness, not the model,
carries end-to-end performance — the retrieval/candidate layer lifts 9B routing from **0.18 to
0.815** and frontier Opus-5 from **0.615 to 0.960**. The residual routing gap to frontier is a
**harness-context artifact**, not a capacity wall: enriching the candidate menu with grounded
one-line descriptions lifts base-9B routing **0.68 → 0.885** (+20.5pp), to **0.915** at a widened
description window, and is paraphrase-robust (0.920) — model-invariant and semantic, not lexical. On
fine-grained Bioconductor method selection, **small+KB matches frontier**: base-9B rises 0.80 → 0.95
(+15pp) with grounded descriptions, landing in the frontier band (0.975–1.0), and four of the newest
open-weight models (2026 releases) reach 0.975–1.000 with the KB — consistent with the external
precedent that compact domain LLMs match frontier systems (LongevityBench, *Cell* 2026). A bounded
concept-CPT pass does yield a real but small knowledge lift (+4.4pp MCQA knowledge-recall, a *lower
bound* from a non-converged partial run). We also report two methodological results that any
on-prem fine-tuning effort needs: (i) a naïve adapter-toggle evaluation silently reported an exact
0.0 train-vs-base delta that was an **evaluation artifact** (the adapter was a no-op at inference),
caught by a startup logit probe; and (ii) single-task LoRA tuning causes **negative transfer**
across prompt formats (−7pp autofix), which format-matched joint training repairs. We conclude that
the durable levers for retrieval-grounded agentic bioinformatics are **the best base the hardware
allows + the harness (retrieval, grounded candidate descriptions, rule+LLM extraction)**, and that
the honest value of on-prem training is cost control and data sovereignty — not a higher score.

---

## 1. Introduction

Agentic assistants for bioinformatics translate natural-language intent into executable analyses:
selecting workflows, extracting parameters, diagnosing failures, interpreting outputs. In production
(BioMate) these are served by an ensemble of LLM calls across ~28 distinct tasks; in the default
configuration that layer calls a frontier cloud model.

**Problem.** A substantial fraction of prospective deployments cannot send data — or even metadata
and prompts — to an external API (air-gapped sites, data-sovereignty jurisdictions), and cloud
inference cost is unbounded at scale. The requirement is a *self-hosted* model that runs inside the
customer's network and approaches cloud quality on BioMate's task suite. This is a **strict-domain**
setting: the model needs deep, reliable competence over a bounded catalog of workflows, parameters,
ontologies, and failure modes, not open-ended world knowledge.

**The question, sharpened.** The intuition that motivated this project was that a domain fine-tune
would *improve* quality. The honest result is the opposite of a capability story. Measuring the real
production baseline overturned the premise: once the model is given the harness's retrieved
candidate context, a bounded domain fine-tune adds nothing measurable to the end-to-end score.

**Single core claim.** *An on-premise domain LLM is a cost and compliance enabler, not a capability
win.* Bounded domain adaptation does not move the end-to-end system bar; the correct lever is the
best base the hardware allows plus the harness (retrieval, grounded candidate descriptions, rule+LLM
extraction). A small model **plus the knowledge base** matches frontier on the discrimination tasks
that drive the product, which is exactly what makes on-prem viable — the value is running privately
and cheaply, not scoring higher.

**Contributions.**
1. A **task-grounded map** of every LLM call in a production bioinformatics assistant (28 tasks),
   partitioned into structured (classify/select/extract), generative, and knowledge tasks, each with
   a per-task verifier.
2. A **grounded, leakage-controlled data-generation pipeline** that reverse-generates training
   queries from real DB artifacts (workflow/tool metadata, parameter schemas, execution logs) and
   verifies them with deterministic checks, an independent-model auditor, and overlap gates against
   the held-out benchmark.
3. A **confound-aware evaluation** (2×2 for routing) and a production-harness baseline establishing
   that **retrieval/candidate context — not weight tuning — carries end-to-end performance**, with a
   bounded SFT giving no end-to-end advantage over base.
4. A **harness-side fix with a measured, overfitting-controlled result**: grounded candidate
   descriptions close most of the routing gap to frontier, model-invariantly.
5. Two **methodological results** on-prem fine-tuning efforts need: the adapter-no-op evaluation
   artifact (with a logit-probe guard) and format-specific negative transfer (with a
   format-matched-joint-training fix).
6. A **contrastive retriever** with honest, leakage-separated recall numbers.

---

## 2. Related work and positioning

- **Domain-adaptive continued pretraining / mid-training.** GAP-Replay (Meditron) and the
  open-base → mid-train-on-literature+code → RL-on-proprietary-data recipe motivate our corpus and
  replay-mix design; mid-training is a distributional bridge between the base prior and the domain.
- **SFT data generation.** Self-Instruct, Alpaca, Evol-Instruct/WizardLM, Orca, Magpie, PersonaHub,
  and APIGen/APIGen-MT define the design space. We borrow Evol-Instruct/PersonaHub *diversity* and
  APIGen *grounding-in-real-tools*, but deliberately avoid paraphrasing a target's own description
  (which teaches surface matching, not grounding) and add explicit overlap gating.
- **Self-evolving agents.** STaR/ReST-EM (generate → filter by correctness → fine-tune → repeat)
  beats human-data-only SFT; the dominant risk is **model collapse** from training on self-generated
  data, which we mitigate by grounding the verifier in real execution/logs rather than self-judgment.
- **Biomedical LLMs: specialist vs generalist.** Domain-specialized models (BioMistral, OpenBioLLM,
  Meditron, Aloe, HuatuoGPT) frequently *fail to beat their generalist base* on contamination-
  controlled data, and for retrieval-grounded tasks in-context retrieval tends to beat parametric
  domain fine-tuning. This literature *predicts* our central result.
- **Frontier life-science models.** Closed models such as the reported GPT-Rosalind are described as
  trained on a small set of common workflows and interfaced to public databases with "skepticism
  tuning" — i.e., *skill in weights, knowledge in retrieval, grounding for safety*. LifeSciBench
  provides an evaluation north-star. We mirror the design with open weights.
- **External precedent — compact domain LLMs match frontier.** The LongevityBench *Cell* 2026 cover
  study introduces an open benchmark (17 tasks, 5 biodata domains), ranks 18 frontier systems, and
  releases a family of 5 compact "Longevity-LLMs" (0.6B–9B) built on Liquid AI LFM2 and Alibaba
  Qwen3/Qwen3.5 — the **same base family** as BioMate's base-Qwen3.5-9B. The compact models
  **matched or exceeded all 16 frontier systems evaluated**, with L-Qwen3.5-9B the highest-scoring
  of 26 systems (0.868 vs 0.685 concordance on DNA-methylation age prediction). Their thesis —
  *curated domain training + domain optimization matter more than raw size* — is external support
  for the small-model / on-prem positioning. We cite it as precedent that small-can-match-frontier,
  while being explicit that BioMate's own result locates the lever in the *system/harness*, not the
  fine-tune (see Appendix A for the DOI-verification caveat on this reference).

**Gap we occupy.** No open, agentic LLM orchestrates bioinformatics *workflows* over a real tool
catalog with grounded, leakage-controlled data and execution-verified evaluation, and then reports
the *honest* finding that the fine-tune is not the lever.

---

## 3. System and tasks

BioMate exposes a catalog of **4,209 workflows across ~36 curated domains (42 raw tags) and 12,312
tools**, with rich metadata (input/output types, tools used, parameter schemas, scientific context,
execution status/errors); a **validated subset of 1,092 workflows** carries clean real-execution
evidence (`real_exec_status IN ('ok','ok_warnings')`). Breadth (4,209) and validated capability
(1,092) are cited separately throughout and never conflated (ground truth:
`docs/20261004_CATALOG_COUNT_RECONCILIATION.md`; source `backend/database/galaxy_ai_tools.db`).

An audit of the codebase identified **28 LLM-backed tasks (T01–T28)**. We target the structured,
verifiable, high-frequency cluster: intent classification (T01), domain inference (T03), workflow
routing (T05), schema-grounded parameter resolution (T06), workflow-modification classification
(T10), log diagnosis (T18), autofix/QC remediation (T19), and parsed-output interpretation (T20).

**Design principle — skill in weights, knowledge in retrieval.** Volatile knowledge (which workflows
exist, their schemas, biology facts) is supplied at inference via retrieval; the model is trained on
the transferable *skill* of operating over that retrieved context. This keeps the model robust to
catalog change (no retraining when the catalog updates) and is consistent with both the
biomedical-LLM evidence and the design of frontier life-science models. The results below show this
division is not just elegant but load-bearing: it is *why* the fine-tune is not the end-to-end lever.

---

## 4. Methods

### 4.1 Grounded, leakage-controlled data generation (11 task families)

Every SFT example is anchored to a real artifact; we never paraphrase the target's own description
(anti-circularity):
- **Routing (T05):** query reverse-generated from a workflow's real `input_types`/`tools_used`/
  `output_types` + a sampled researcher persona; supplemented with real GEO study descriptions whose
  assay type deterministically labels the pipeline.
- **Parameters (T06):** schema-valid values are *sampled* from a workflow's `params_schema`, then a
  query is generated to *imply* them without naming keys (APIGen-style); gold extraction is
  schema-valid by construction, and distractor parameters test restraint.
- **Diagnosis/autofix (T18/T19):** grounded in real `real_exec_err` logs.
- Further families: conditional-parameter restraint, hierarchical phase→step decomposition,
  cross-workflow decomposition, abstention/clarification, workflow generation, protocol QC.

Anti-patterns deliberately avoided: target-description paraphrasing; restating default parameters
(conditional-parameter restraint — measured ≈8.2 shown → 1.4 gold on average); flat step lists
(decomposition gold is a phase→step DAG; 74% of examples multi-phase); hallucinating a missing
required parameter (clarify teaches abstention).

**Verification (multi-stage, grounded).** (1) *Deterministic gates:* schema membership, legal values
vs `allowed_values`/type, a name-leak guard, and character/token-3gram + substring overlap against
the held-out RealBio benchmark (<0.5 required; observed maxima ≤0.24). (2) *Independent auditor:* a
**different model** than the generator scores realism/correctness/non-circularity/restraint; for
execution-verifiable tasks the deterministic check is authoritative.

**Paraphrase-diversity layer.** An early version used format jitter (swapping fixed delimiters),
risking format-specific gains. We replaced it with genuine paraphrase augmentation: each request is
reworded into K≈5 variants from a 10-voice persona/style bank; the assistant target and any
structured block (schema, candidate list) are held verbatim; real execution-error logs are left
untouched. Result: **3,969 → 17,291 examples** (+13,322 distinct deduped rewrites; ≈4.5× on the 2,982
paraphrasable rows).

### 4.2 Mid-training / concept-CPT corpus

Structured internal knowledge was verbalized (triples → sentences) into natural-language documents
for continued pretraining. Two corpora are reported:
- An early **~37M-token** mid-training corpus (code, internal DB text, verbalized ChEBI/GO/HPO/EDAM/
  SO ontologies, GTN tutorials, down-weighted Hetionet, workflow-ordering metadata).
- A **concept-dominant CPT mix** `midtrain_domain_concept_norm2.jsonl` (2.8 GB, **593,367,127
  tokens**; composition: pmc_fulltext 166,724 + pmc_review 23,562 + db_tool 32,430 + db_workflow
  20,785 + gtn 1,715 + openstax 795 + wikibook 8,180; bg_repeat 5), with general-corpus replay
  (REPLAY_FRAC 0.3) to mitigate catastrophic forgetting.

The domain-vs-general replay ratio is treated as a hyperparameter to be swept, not fixed.

### 4.3 Contrastive retriever

BioMate routes by first retrieving candidate workflows, then having the LLM select; the retriever is
the ceiling on routing quality. We fine-tuned `BAAI/bge-small-en-v1.5` with InfoNCE
(MultipleNegativesRankingLoss): anchor = researcher query; positive = the correct workflow's
verbalized document; **hard negatives** = the confusable workflows the existing hybrid TF-IDF+dense
retriever ranks above the gold. Training set: 2,206 queries → 4,412 (query, +gold, −hard) triplets;
a frugal CPU proof (batch 8, 2 hard negatives, 1 epoch).

### 4.4 Training

QLoRA (4-bit NF4, r=16, all projection modules, assistant-token-only loss) on the base model, with a
shared prompt module making training and evaluation protocols byte-identical. The canonical
adapter evaluation merges the adapter and serves merged and base independently under vLLM (removing
adapter-toggle ambiguity; see §4.5 and §6.1).

### 4.5 Evaluation

All end-to-end numbers are produced by the open, objectively-scored **RealBio harness** (shared
`score.py` over committed `results/<model>/<task>.jsonl`). Two conventions:
- **Primary metric = LLM + harness (catalog mode)** — the number the shipped system actually
  produces. The **bare** (LLM-alone, no candidates) column is a *diagnostic only*; the product never
  runs bare, so bare never gates a decision.
- **Routing 2×2 confound design.** For the one task with a candidate-context confound (routing) we
  evaluate {base, SFT} × {bare, catalog} with paired bootstrap 95% CIs, isolating the
  candidate/retrieval effect from the true fine-tuning lift.

---

## 5. Results

### 5.1 The harness is the differentiator, not the LLM

Routing, n=200 (`20261004_REALBIO_LLM_VS_HARNESS.md`; committed `results/` + `leaderboard.csv`):

| Model | LLM bare (own knowledge) | LLM + catalog (retrieval) | full BioMate harness |
|---|--:|--:|--:|
| base Qwen3.5-9B | 0.18 | **0.815** | — |
| SFT (our tuned 9B) | 0.285 | 0.805 | — |
| Claude Opus-5 (frontier) | 0.615 | 0.960 | — |
| BioMate product (LLM mixture) | — | — | **0.965** |

The candidate/retrieval layer lifts the 9B from **0.18 → 0.815** (+63pp) and Opus from 0.615 → 0.960
(+35pp). Hand any LLM the harness's retrieved context and routing jumps into the high band — the
harness carries the task.

### 5.2 Bounded SFT adds nothing end-to-end

With the harness (catalog mode), our SFT ≈ base on **every** task; the only place SFT exceeds base is
*bare* routing (0.285 vs 0.18) — a mode the product never uses
(`20261004_REALBIO_LLM_VS_HARNESS.md`):

| Task (metric) | base 9B | SFT 9B | Δ (SFT−base) |
|---|--:|--:|:--:|
| routing — catalog (acc) | 0.815 | 0.805 | −0.010 |
| routing — bare (acc) | 0.18 | 0.285 | +0.105 |
| param_prefill (F1) | 0.664 | 0.657 | −0.007 |
| protocol_QC (acc) | 0.43 | 0.43 | 0.000 |
| autofix (cat-acc) | 0.87 | 0.85 | −0.020 |
| boin (MTD exact) | 0.778 | 0.778 | 0.000 |
| pbpk (within-2-fold) | 0.067 | 0.0 | −0.067 |
| drug_discovery (Spearman) | 0.70 | 0.70 | 0.000 |
| workflow_gen (acc) | 0.50 | 0.50 | 0.000 |

**Net: the bounded SFT does not improve BioMate.** Capacity still matters a little — frontier+catalog
(Opus 0.960) beats 9B+catalog (~0.81) by ~15pp — but *tuning a 9B* did not close that gap. The gap is
capacity, not domain adaptation. (`qwen3.8-27b` is excluded from the leaderboard as a failed run with
`None` predictions — see Appendix B; the committed `results/qwen_qwen3.8-27b/` directory exists but is
not scored.)

### 5.3 The routing gap to frontier is a harness-context artifact, not a capacity wall

Item-level decomposition of the 31-item base-vs-frontier routing gap (n=200): **0/31 are retrieval
misses — 100% are selection misses** (gold was always in the 91-name candidate menu; base picked a
wrong same-domain sibling). The root cause is that the legacy catalog prompt gave the model **bare
workflow names only**; a 9B often cannot map an opaque id (`nf-core/differentialabundance`) to what
it does, while a frontier model recognizes it from pretraining. Enriching the candidate menu with a
grounded one-line description + input types (from the workflow catalog's own metadata) is a
**model-invariant** fix (`20261004_CLOSE_THE_GAP_ROUTING.md`, measured on the real base 9B served on
vLLM):

| base 9B routing (catalog / LLM+harness) | accuracy |
|---|--:|
| NAMES menu (legacy), no-think | 0.680 |
| DESCRIBED menu (the fix), no-think | **0.885** (+20.5pp; 47 recovered, 6 broken) |
| DESCRIBED menu, widened window W=200, no-think | **0.915** |
| prior base catalog *with* thinking (leaderboard) | 0.815 |
| frontier Opus catalog | 0.960 |
| full product | 0.965 |

Described-no-think (0.885) already **beats** base-with-thinking (0.815) — descriptions more than
compensate for dropping chain-of-thought. **Overfitting controls:** the 47 recovered items spread
across 26 distinct workflows (only 2/47 on hand-engineered disambiguation targets); and rewriting all
200 queries with a different model (paraphrase, no workflow names) preserves the lift (described
0.885 → 0.900; names 0.680 → 0.675), so the gain is **semantic, not lexical echo**. Widening the
description window closes routing to ~0.915–0.920 model-invariantly and paraphrase-robustly. This is
also the architecturally correct place to fix routing per the system's own doctrine (retrieval owns
selection-from-catalog; the LLM is not the deterministic-mapping lever).

### 5.4 Small + KB matches frontier (Bioconductor method selection)

On fine-grained Bioconductor method selection (`20261004_BIOC_SELECTION_MATRIX_RESULTS.md`, hardened
40-item set, bare names vs +KB-described candidates):

| model | bare top1 | +KB top1 | KB dividend | invalid-regime bare→kb |
|---|--:|--:|--:|--:|
| openai/gpt-5.6 | 1.000 | 1.000 | 0 | 0 → 0 |
| anthropic/claude-opus-5 | 1.000 | 0.975 | −2.5pp | 0 → 0 |
| google/gemini-3.1-pro-preview | 0.975 | 1.000 | +2.5pp | 0 → 0 |
| deepseek/deepseek-v4-pro | 0.825 | 0.923 | +9.8pp | 0 → 0 |
| **base Qwen3.5-9B (on-prem)** | **0.800** | **0.950** | **+15.0pp** | **0.125 → 0** |

The **KB dividend scales inversely with model strength**: frontier already knows these packages (≈0
dividend), while the small on-prem 9B gains +15pp (0.80 → 0.95), landing next to frontier. Critically,
the 9B made invalid-regime choices (e.g. ORA on ranked data) on **12.5%** of items without the KB and
**0%** with it — the KB is an accuracy *and* a correctness/safety lever for a small model. A
**2026-10-05 open-LLM refresh** (four newest open-weight releases: deepseek-v4.1-flash, glm-5.3,
qwen3.8-2.4t-a95b, kimi-k3) confirms rather than changes the story — all four reach **0.975–1.000**
top1 with the KB, matching the frontier band and the on-prem 9B+KB (0.95), every KB dividend positive
and inversely scaled with bare strength (run cost $0.41). This is the direct evidence that *the KB,
not the model size, lets a small on-prem system pick the right method from scientific context* — and
the in-domain analog of the LongevityBench *Cell* "small-matches-frontier" precedent.

The product composition is quantified on the same set: live full-catalog retrieval recall@8 = 0.825
but retrieval@1 only 0.375 (ranking-limited, not coverage-limited); a retrieve → KB-grounded
selection composite reaches **0.80 end-to-end** with conditional-select 0.97 — i.e. *selection is
essentially solved; the remaining ceiling is retrieval recall, not the LLM.* A diagnosed −8.0
subworkflow penalty (`unified_workflow_search.py:1814-1818`) is the retrieval-ranking root cause; a
gated fix is shipped in code with an offline-verified predicted effect (37/40 queries escape the
penalty) but **dev-verification is pending** (Appendix A).

### 5.5 Concept-CPT: a real but bounded knowledge lift (lower bound)

A **bounded** 9B concept-CPT+SFT run (300 CPT + 500 SFT steps — a *partial* pass of the 593M-token
concept mix, **not** a converged model) improves open-book MCQA domain knowledge
(`20261005_9B_CONCEPT_CPT_EVAL_CORRECTED.md`, re-scored from committed prediction strings with a
corrected grader):

| task | base (orig 9B) | domainpro (concept-CPT + SFT) | Δ | invalid (both) |
|---|--:|--:|--:|--:|
| knowledge_recall | 0.679 (76/112) | **0.723 (81/112)** | **+4.4pp** | 0 |
| scientific_qa | 0.604 (90/149) | 0.604 (90/149) | 0 | 0 |
| overall | 0.636 (166/261) | 0.655 (171/261) | +1.9pp | 0 |

The originally-recorded artifact showed knowledge_recall 0.018 with 256/261 "invalid" — a **grader
bug** (`re.fullmatch` required the whole decoded string to be a bare letter; the SFT model answers in
option-text form `"D) Thyroid agenesis."`). The corrected leading-option-letter extractor leaves the
base **unchanged** (0.636 → 0.636, a fairness proof that it adds no false positives) and recovers the
true domainpro score. **Caveats carried forward:** the +4.4pp is a **lower bound** from a bounded,
non-converged run; scope is open-book MCQA only (not execution-task success — the grounded workflow
eval was prepared but `execution_status=NOT_RUN`); the leakage filter is exact-stem only; no CIs. The
*direction* is positive, which is why a fuller CPT pass is the sized next lever (§8) — but on the
primary end-to-end metric (§5.1–5.2), no CPT result yet moves the LLM+harness bar.

### 5.6 Contrastive retriever: honest, leakage-separated recall

The contrastive retriever lifts routing retrieval recall sharply, but the two evaluation splits must
be reported separately (`20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md` §4):

| Metric | Before | After | split |
|---|--:|--:|---|
| recall@1 | 0.233 | 0.767 | random split — **leakage-inflated** |
| recall@5 | 0.377 | 0.915 | random split — **leakage-inflated** |
| recall@1 | 0.244 | **0.399** | family holdout (169 workflows unseen) |
| recall@5 | 0.374 | **0.694** | family holdout (169 workflows unseen) |

**Headline recall@5 = 0.694 (family holdout).** The random split leaks (the same workflow appears in
train and test) and its 0.915 is reported only as explicitly leakage-inflated. The contrastive lift
is real and generalizes to unseen workflows (not memorization); 0.399@1 / 0.694@5 is the honest
unseen-workflow floor, with production sitting between the two splits since most catalog workflows do
accrue training queries. The proof is CPU-under-scaled (8.6 GB RAM, batch 8, 1 epoch); a GPU
configuration is expected to improve further. A separate hybrid retriever (lexical+dense) reaches
recall@20 = 0.94–0.95 over the full catalog, confirming routing is a retrieve-then-rank problem whose
durable lever is retrieval, not weight tuning.

### 5.7 Transfer failure and the format-matched joint-training fix

A routing LoRA trained on a *bespoke* prompt format (+3pp on that format) transferred **nothing** to
the production harness (catalog 0.815 → 0.795) and caused **−7pp on autofix** (0.87 → 0.80) —
single-task tuning induced negative transfer because fine-tuning gains are specific to the exact
prompt format and label space (`docs/20260912_onprem_llm/MANUSCRIPT.md` §5). Rebuilding the data in
the *exact* harness formats/label spaces and training **one joint LoRA** across routing+param+autofix
recovered real, targeted gains with **no negative transfer**:

| Task | Base | routing-LoRA (single) | Multitask-LoRA (format-matched) |
|---|--:|--:|--:|
| routing bare | 0.18 | 0.17 | **0.285** (+10.5pp) |
| routing catalog | 0.815 | 0.795 | 0.805 |
| autofix | 0.87 | 0.80 (−7pp) | 0.85 (held) |
| param F1 / precision | 0.664 / 0.77 | 0.646 / — | 0.657 / **0.823** |
| param must-not-fill violations | 53 | 49 | **36 (−32%)** |
| workflow_gen / protocol / boin / dd | 0.50/0.43/0.78/0.70 | (n/a) | all held |

Gains concentrate where matched data was added (bare-routing recall; parameter **restraint** —
−32% over-fills); untuned tasks are preserved; already-strong tasks (autofix) are near ceiling.
**Note that even here the catalog-mode (product) routing number barely moves (0.815 → 0.805),
consistent with §5.2** — the realized value is *restraint* and *format adherence*, not a higher
end-to-end bar. A planned **round-2** joint run (adding protocol/workflow_gen, balancing param,
de-skewing autofix) was fully built (1,253 balanced examples across five tasks) **but not trained,
due to an unrecoverable GPU-host failure** — the data and pipeline are ready; realized gains are from
the first joint LoRA only. The lesson — *train on the metric you report, jointly* — is a prerequisite
for any on-prem fine-tuning, but it does not overturn the cost/compliance conclusion.

### 5.8 Methodological: the adapter-no-op evaluation artifact and its guard

An earlier 27B QLoRA SFT run trained correctly (loss 1.185 → 0.604 over 200 steps) yet reported a
train-vs-base delta of **exactly 0.0 on every benchmark**, including a *continuous* recall metric
across 37 items. An exact 0.0 on a continuous metric across many items is only possible if base and
SFT produced identical outputs — i.e., the adapter was a **no-op at inference**, not a training
failure. Root cause: the harness toggled the adapter in-process with `disable_adapter()`, which can
silently fail to take (wrong path, quantization mismatch). **Guard:** a startup **logit probe** runs
one forward pass with the adapter enabled and one disabled and fails loudly if the max absolute logit
difference is below threshold; the canonical evaluation merges the adapter and serves merged vs base
independently under vLLM. *For adapter-based fine-tuning, never trust a same-process enabled/disabled
delta without a positive control that the adapter changes logits at all.*

### 5.9 On-prem multimodal figure reading (secondary)

With the vision tower enabled, the same on-prem base read a controlled figure exactly — recovering
the title, axis label, all four values, and the correct highest/lowest samples — demonstrating
on-prem figure interpretation with exact value reading, without a separate model
(`docs/20260912_onprem_llm/MANUSCRIPT.md` §5). This is a single-figure demonstration, not a
quantified benchmark (Appendix A).

---

## 6. Discussion

**Cost/compliance, not capability.** On the production harness, a strong-enough base plus a candidate
list already achieves 0.815 on routing and is competitive across the suite; a bounded fine-tune adds
targeted *restraint* and *format adherence*, not a higher end-to-end score. Measuring the real
baseline overturned the premise we initially acted on: param-prefill and autofix are **not**
weak-base tasks (0.66 F1 and 0.87 on the harness). The honest conclusion is that the value of on-prem
training is **running privately and cheaply**, and that the levers that move the bar are the **best
base the hardware allows + the harness** (retrieval, grounded candidate descriptions, rule+LLM
extraction).

**Knowledge in retrieval, skill in weights — empirically load-bearing.** The routing gap being 100%
selection-miss and closable by *showing descriptions* (model-invariant, paraphrase-robust) is direct
evidence that the discriminating knowledge belongs in the retrieved context, not the weights. The
Bioconductor result — small+KB matching frontier, with the KB also eliminating invalid-regime choices
— is the same mechanism at method granularity.

**Train on the metric you report.** A LoRA that improved one prompt format transferred nothing to a
different format and harmed an untuned task; "train == eval" must mean the *production* format, and
tuning must be *joint* across the cluster. This also exposes the tension the field warns about —
training to a benchmark's exact label space risks benchmark adaptation over capability — so we keep
**retrieval** as the durable lever and flag which gains are capability (restraint, format adherence,
real-log diagnosis) vs format-fitting.

**The one genuinely LLM-bound residual is uncertain.** Multi-task decomposition/orchestration is the
remaining candidate for a capability where model quality (not harness engineering) is the lever
(base 0.40 vs frontier 0.60 structure accuracy at coverage 1.0). **But that number is largely a
metric artifact** (`20261004_CLOSE_THE_GAP_ROUTING.md` §CORRECTION): the coarse 4-class
`_structure_of` classifier mislabels finer-but-reasonable decompositions, so 0.60 understates true
quality and 0.40/0.60 is **not** a trustworthy LLM-bound proof. We explicitly do not cite 0.40/0.60
as a capability result; a DB-grounded node-F1/edge-F1 decomposition benchmark is required before the
decomposition claim can be made (§8).

---

## 7. Limitations

- **No converged end-to-end training numbers.** Mid-training/CPT and SFT final capability numbers are
  from *bounded* runs; the concept-CPT +4.4pp is a lower bound on a non-converged partial pass.
- **Round-2 joint training built but not trained** (unrecoverable GPU-host failure); realized gains
  are from the first joint LoRA only. Robust, resumable GPU orchestration was a primary cost here.
- **Reverse-generated queries are synthetic**; realism is enforced by an auditor (itself a model),
  not by real users — execution/schema checks are the stronger gate.
- **Single catalog, single query distribution.** Absolute magnitudes may differ on a new catalog or
  user distribution; the two overfitting mechanisms that would make the description lift fake
  (phrasing echo, hand-tuned-workflow concentration) are empirically ruled out, but distribution
  shift is not.
- **Decomposition metric artifact** (§6): 0.40/0.60 is not a trustworthy capability result.
- **Leakage controls** are exact-stem / overlap-threshold, not semantic or source-family
  certification; a source-family holdout is required for a leakage-clean CPT claim before external use.
- **Retriever proof is CPU-under-scaled**; the family-holdout 0.694@5 is the honest floor, not a
  GPU-optimized number.
- **The retrieval-ranking fix and production description backfill are shipped in code but
  dev-unverified** (Appendix A).
- **Multimodal capability is a single-figure demonstration**, not a benchmark; specialized modalities
  (cryo-EM, histology) are unquantified.

---

## 8. Future work

1. **Full-corpus CPT decision row** (the one experiment that would change the conclusion): serve the
   fuller CPT-merged base + SFT adapter, run the RealBio **catalog** runner (same retrieval layer),
   and add the LLM+harness score. *If* full-corpus catalog ≈ base catalog (≈0.81), the cost/compliance
   conclusion is firm; *if* it materially exceeds base, domain CPT is a scaling lever worth the GPU
   spend. (`20261004_REALBIO_LLM_VS_HARNESS.md` "Still pending".)
2. **Ship and verify the routing/selection harness fixes** on dev: production `description := annotation`
   backfill, the gated subworkflow-penalty fix, the widened description window, and route retrieved
   top-k through KB-grounded selection rather than retrieval rank-1.
3. **DB-grounded decomposition benchmark** (node-F1/edge-F1 over a type-compatibility DAG from
   `workflows.input_types/output_types`), replacing the 4-class metric, before any decomposition
   capability claim.
4. **Run the prepared round-2 joint training** and re-measure per task; stand up the hybrid retriever
   (recall@20≈0.95) as the production front-end with a learning-to-rank reranker.
5. **Independent (non-self) grading** and source-family leakage certification before external
   submission.

---

## Data & Code Availability

- **License:** CC-BY-4.0. **DOI / repository:** [DOI/REPO TBD].
- **Benchmark + scorer:** `evaluation/datasets/public_export/` (RealBio harness, `score.py`,
  committed `results/<model>/<task>.jsonl`, `leaderboard.csv`);
  `evaluation/datasets/bioc_method_selection/` (method-selection matrix, `run_bioc_matrix.py`,
  raw predictions under `results/`).
- **Data generators & trainers:** `evaluation/local_trial/` (`train_retriever_contrastive.py`,
  `paraphrase_augment.py`, `build_paraphrase_v2.py`, `eval_holdout.py`, `eval_holdout_vllm.py`,
  `eval_today.py`, `build_retriever_eval.py`, per-task `generate_*.py` / `build_*.py`).
- **Model/data artifacts (S3, gitignored):** enriched SFT
  `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/sft/multitask_sft_enriched.jsonl`;
  mid-training/concept corpora `.../midtrain_corpus/*.jsonl`, `midtrain_domain_concept_norm2.jsonl`;
  contrastive retriever `.../retriever/bge-routing-contrastive/`; concept-CPT run
  `models_20260919/med/base_domain_today_20261003/` + `…/full_today_20261003_adapter/`; MCQA eval
  predictions `…/eval/med_today_20261003/{base,domainpro}.json`.
- **Catalog source of truth:** `backend/database/galaxy_ai_tools.db`
  (`docs/20261004_CATALOG_COUNT_RECONCILIATION.md`).

## Author Contributions

[AUTHORS TBD] — contributions to be assigned on finalization; no authorship is asserted here.

## References

*(To be formatted; carried forward from the source drafts — verify every entry against the primary
source before submission, per the honesty contract. None are fabricated by this consolidation.)*

- LongevityBench + Longevity-LLMs, *Cell* 189(19):5980–5994.e8 (2026), PII S0092-8674(26)00999-2 —
  **DOI not independently verified in this session** (publisher page returned HTTP 403); confirm DOI
  from the Cell landing page before use (`reference/20261004_REF_longevity_benchmark_and_model.md`).
- Self-evolving-agent surveys arXiv:2508.07407, arXiv:2507.21046; STaR arXiv:2203.14465; ReST-EM
  arXiv:2312.06585; Reflexion; model-collapse (Nature 2024).
- Biomedical specialist-vs-generalist: Fully-Open Meditron; arXiv:2408.13833; Nature Medicine 2026;
  Aloe arXiv:2505.04388; BioMistral arXiv:2402.10373; OpenBioLLM.
- GPT-Rosalind and LifeSciBench (OpenAI, 2026).
- SFT data generation: Self-Instruct, Alpaca, Evol-Instruct/WizardLM, Orca, Magpie, PersonaHub,
  APIGen/APIGen-MT.
- Biomni (*Science* 2025, 10.1126/science.adz4351) — companion BioMate flagship/RealBio arc.
- (See `SELF_EVOLVING_SURVEY.md`, `SMALL_DOMAIN_LLM_SURVEY.md` for the adversarially-verified
  citation sets.)

---

## Appendix A — Flagged / unverifiable numbers and provenance

Numbers below are reported in the source drafts/analyses but were **not independently recomputed from
raw prediction files** in this consolidation; they are cited on the authority of the named committed
artifact. They should be re-derived from the raw `results/*.jsonl` + `score.py` before external
submission.

1. **End-to-end RealBio per-task numbers** (§5.1, §5.2, §5.7) — taken from
   `20261004_REALBIO_LLM_VS_HARNESS.md` and `leaderboard.csv`. The Qwen3.8-Max row of
   `leaderboard.csv` was spot-checked and matches draft 2's hosted-frontier column exactly
   (0.345/0.860/0.692/0.500/0.460/0.000/0.111/0.700); the base/SFT (9B) per-task cells were **not**
   re-scored from raw predictions here.
2. **Routing description-fix numbers** (§5.3: 0.680/0.885/0.915/0.900/0.920) — from
   `20261004_CLOSE_THE_GAP_ROUTING.md`; served-9B vLLM run, not re-run here.
3. **Bioconductor matrix** (§5.4) — from `20261004_BIOC_SELECTION_MATRIX_RESULTS.md`; raw predictions
   exist under `evaluation/datasets/bioc_method_selection/results/` (incl. `base-9B_{bare,kb}.jsonl`)
   but were not re-scored here. The retrieval-ranking root-cause fix is **shipped in code,
   dev-verification pending** ("HELD for explicit go" in the source doc).
4. **Concept-CPT +4.4pp** (§5.5) — re-scored in the source doc from committed prediction strings;
   this consolidation did not re-run that re-scoring. **Bounded/non-converged; MCQA-only; lower bound.**
5. **Contrastive retriever recall** (§5.6) — from `20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md`; CPU
   proof, not re-run here. Random-split 0.767/0.915 is explicitly leakage-inflated and reported only
   as such; **headline = family-holdout 0.694@5**.
6. **Paraphrase multiplier 3,969 → 17,291** and **593,367,127-token concept mix** (§4.1, §4.2) — from
   the source drafts/`20261005_9B_CONCEPT_CPT_EVAL_CORRECTED.md`; not re-counted here.
7. **~37M-token early mid-train corpus** (§4.2) — draft-1 figure; the table there lists *byte* sizes
   (code 71 MB etc.), so "37M tokens" is the draft's stated token count, not derivable from the byte
   table. Carried forward as-stated; verify before use.
8. **LongevityBench *Cell* numbers** (§2) — press-sourced in the reference note; the publisher page
   blocked automated fetch (403). Volume/pages and PII are cross-verified; **DOI and open-access link
   are unverified** — confirm before citing.
9. **Multimodal figure-reading** (§5.9) — a single qualitative demonstration, not a quantified
   benchmark.
10. **"8.2 shown → 1.4 gold" conditional-param average and "74% multi-phase"** (§4.1) — draft-1
    descriptive statistics; not re-derived here.

## Appendix B — Draft-vs-draft conflicts and their resolution

| # | Conflict | Draft 1 (20260918) | Draft 2 (20260912 MANUSCRIPT) | Resolution (and evidence) |
|---|---|---|---|---|
| B1 | **Catalog size** | 4,017 workflows / 36 domains | 4,200 workflows / 36 / 12,312 tools | **4,209 workflows (1,092 validated) / ~36 curated (42 raw) / 12,312 tools.** Ground truth `docs/20261004_CATALOG_COUNT_RECONCILIATION.md` (direct DB query). Both drafts' figures were earlier snapshots. Breadth and validated cited separately. |
| B2 | **Base model identity** | "two-model plan: small ~4B + ~27B" (plan, not run) | "Qwen3.8-27B (ours)" served, numbers 0.18/0.815/0.87/0.664/0.778/0.067/0.70/0.50 | **Base = Qwen3.5-9B.** The *identical* per-task numbers appear in the later (2026-10-04) `20261004_REALBIO_LLM_VS_HARNESS.md` attributed to `base` (9B); the committed results dir is `results/base/` + `base-9B_*.jsonl` in the bioc set; manuscript-plan, the LongevityBench ref, and project memory all call it **L-Qwen3.5-9B**. Draft 2's "27B (ours)" label is a **mislabel of the 9B base**. A *separate* `results/qwen_qwen3.8-27b/` dir exists but is an excluded failed run (`None` predictions per `20261004_REALBIO_LLM_VS_HARNESS.md`). Resolved to 9B. |
| B3 | **Frontier comparator** | (none — plan only) | "Qwen3.8-Max (hosted)" per-task column | **Both real, distinct comparators.** `leaderboard.csv` confirms the Qwen3.8-Max row exactly; Opus-5 (routing bare 0.615 / catalog 0.960) is the headline frontier in the later doc. Headline uses the RealBio three-level table (base 9B / SFT 9B / Opus-5 / product); the Qwen3.8-Max column is retained as a leaderboard row, not as the frontier headline. No conflict in values — resolved as two comparators at different dates. |
| B4 | **Central result framing** | retriever + grounded SFT + paraphrase (capability-building tone) | transfer-failure as the central result; "27B on par with far-larger hosted model" | **Unified under cost/compliance.** Both drafts' substantive findings are preserved, but subordinated to the single claim that the fine-tune does not move the end-to-end bar (§5.2). "Small on par with far-larger model" is re-cast as *supporting* evidence for small+KB≈frontier (§5.4), using the honest 9B label (per B2). |
| B5 | **Retriever recall headline** | random-split recall@5 0.915 prominent; family-holdout 0.694 secondary | (retriever not the focus) | **Headline = family-holdout 0.694@5**; random-split 0.915 reported only as explicitly leakage-inflated (per the task mandate and draft-1's own "the random split leaks" note). |
| B6 | **Round-2 joint training status** | n/a | "built (1,253 examples) but not trained — GPU-host failure" | Preserved verbatim as a limitation (§5.7, §7): built, not trained; realized gains from first joint LoRA only. |
| B7 | **Zero-delta finding** | "evaluation artifact, not training failure" + logit probe | same finding (§5) | Consistent across drafts; kept as a methodological result (§5.8). Note the loss-curve run is described in draft 1 as "27B QLoRA"; retained as draft-1's wording for that *earlier* run (distinct from the 9B RealBio base of B2) and flagged as such — this is the one place "27B" is kept, because it refers to a different, earlier training run, not the RealBio-served base. **If the earlier loss-curve run was also a 9B, this label needs correction — FLAGGED, cannot resolve from available artifacts.** |

## Appendix C — User-input blockers (decisions this consolidation cannot make)

1. **Authorship** — `[AUTHORS TBD]`; author list, order, and corresponding author must be supplied.
2. **Target venue** — manuscript-plan §2.4 says "a systems/ML-for-science or infrastructure venue";
   not finalized. Framing (systems paper vs ML-for-science) affects section emphasis.
3. **DOI / repository / CC-BY-4.0 deposit** — `[DOI/REPO TBD]`; the code+data availability statement
   needs a minted DOI and a public repo decision (which S3 artifacts are released vs described).
4. **LongevityBench *Cell* DOI** — confirm the exact DOI and open-access link before the reference is
   used externally (Appendix A#8).
5. **B7 "27B" earlier loss-curve run** — confirm whether the 200-step loss-curve run (§5.8) was a 27B
   or a 9B; the draft-1 text says 27B but B2 shows the RealBio base is 9B. Cannot resolve from
   committed artifacts.
6. **Full-corpus CPT decision row** — the one experiment that could upgrade or qualify the core claim
   (§8.1) is still pending GPU spend; the manuscript currently states the conclusion conditional on it.
7. **Independent (non-self) grading** — required before external submission (manuscript-plan §4);
   not available in this consolidation.
