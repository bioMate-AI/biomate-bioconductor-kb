# Building a Private, On-Premise Domain LLM for Bioinformatics Workflow Orchestration

**A data-generation, contrastive-retrieval, and continued-pretraining recipe for BioMate**

*Working manuscript — 2026-09-18. Corresponding system: BioMate (cloud + air-gapped bioinformatics execution engine).*

---

## Abstract

Sensitive genomic and clinical data frequently cannot leave an institution's network, which
rules out cloud LLM APIs for a large class of bioinformatics deployments (air-gapped sites,
data-sovereignty jurisdictions). We describe the design and empirical evaluation of a **private,
on-premise LLM** that drives BioMate's ~28 language tasks — workflow routing, parameter
extraction, hierarchical and cross-workflow decomposition, clarification/abstention,
execution-trace diagnosis, and protocol QC. Our contributions are: (1) a **domain-adaptive
mid-training corpus** (~37M tokens) verbalized from internal databases, ontologies, knowledge
graphs, and workflow code; (2) a **grounded SFT data-generation pipeline** that anchors every
example in real workflow artifacts rather than paraphrasing a target's own description, spanning
11 task families; (3) a **paraphrase-diversity layer** that rewords each request across a
persona/style bank (3,969 → 17,291 examples, +13,322 distinct rewrites) to prevent
format-overfitting; and (4) a **contrastive retriever** (InfoNCE over mined hard negatives) that
lifts routing retrieval recall@1 from 0.233 to 0.767 and recall@5 from 0.377 to 0.915. We also
report a methodological finding: a naïve adapter-toggle evaluation silently reported a zero
train-vs-base delta that was an *evaluation artifact*, not a training failure, and we describe the
logit-probe guard that catches it. We conclude with a two-model plan (a small model and a ~27B
model) for cost/quality comparison and a cascade deployment.

---

## 1. Introduction

BioMate is a bioinformatics execution engine spanning 4,017 workflows across 36 domains
(transcriptomics, genomics, variant calling, epigenomics, single-cell, proteomics, drug
discovery, metagenomics, cryo-EM, and more). Its assistant layer translates natural-language
researcher requests into concrete, executable workflow invocations. In its default configuration
this layer calls a frontier cloud LLM.

**Problem.** A substantial fraction of prospective deployments cannot send data — or even
metadata and prompts — to an external API. The requirement is a *self-hosted* model that (a)
runs inside the customer's network, (b) generalizes across BioMate's task suite, and (c)
approaches the quality of the cloud model on those tasks. This is a **strict-domain** setting:
the model does not need open-ended world knowledge; it needs deep, reliable competence over a
bounded catalog of workflows, parameters, ontologies, and failure modes.

**Approach.** We adopt the now-standard three-stage recipe for domain LLMs — open base →
domain-adaptive **mid-training** (continued pretraining) → task **SFT** — augmented with a
**retrieval front-end** trained contrastively, and a **grounded RL** stage (design described,
training deferred to GPU). The distinguishing choices are that (i) our SFT data is *grounded in
real artifacts* (verified workflows, real parameter schemas, real execution errors) rather than
distilled from a teacher's paraphrase of the target, and (ii) diversity is injected as an
explicit paraphrase layer so gains transfer across prompt surface forms.

---

## 2. Related work and positioning

- **Domain-adaptive continued pretraining / mid-training.** GAP-Replay (Meditron) and the
  Periodic Labs recipe (open base → mid-train on literature + code → RL on proprietary data)
  motivate our corpus + replay-mix design. Mid-training acts as a distributional bridge between
  the base model's general prior and the target domain.
- **SFT data generation.** Self-Instruct, Alpaca, Evol-Instruct/WizardLM, Orca, Magpie,
  PersonaHub, and APIGen/APIGen-MT define the design space. We borrow Evol-Instruct/PersonaHub
  *diversity* and APIGen *grounding-in-real-tools*, but deliberately avoid the failure mode of
  paraphrasing the target's own description (which teaches surface matching, not grounding).
- **Contrastive retrieval.** InfoNCE / MultipleNegativesRankingLoss with mined hard negatives is
  standard for dense retrievers; we apply it to workflow routing, where the "documents" are
  workflow specs and the hard negatives are the confusable workflows the retriever currently
  ranks above the gold.
- **Knowledge-in-retrieval vs skill-in-weights.** We keep volatile catalog knowledge (which
  workflow, which params) in retrieval and put *skills* (decompose, diagnose, abstain, extract)
  in weights — a division that keeps the model small and the catalog updatable without retraining.

---

## 3. Data

### 3.1 Mid-training corpus (~37M tokens)

We verbalized structured internal knowledge into natural-language documents for continued
pretraining. Sources and approximate sizes (uncompressed JSONL):

| Source | Content | Size |
|---|---|--:|
| `code_corpus` | Bioconductor / Nextflow / workflow code scripts | 71 MB |
| `internal_corpus` | Internal DB text (workflow descriptions, tool metadata) | 39 MB |
| `chebi_corpus` | ChEBI chemical ontology (verbalized OBO) | 18 MB |
| `go_corpus` | Gene Ontology (verbalized) | 14 MB |
| `gtn_corpus` | Galaxy Training Network tutorials | 7 MB |
| `hpo_corpus` | Human Phenotype Ontology | 5 MB |
| `hetionet_corpus` | Hetionet biomedical KG (central metaedges) | 5 MB |
| `db_kg_corpus` | Internal tool/DB knowledge graph | 3.5 MB |
| `workflow_order_corpus` | Step-ordering / DAG structure from workflow metadata | 3 MB |
| `edam_corpus`, `so_corpus` | EDAM + Sequence Ontology | ~1.3 MB |

Design decisions worth recording: (a) **Hetionet was down-weighted** to biomedically-central
metaedges after an early over-representation of gene–gene edges made it off-topic; (b) a
degenerate `tool_compatibility` relation (all rows identical) was dropped in favor of
step-metadata-derived workflow ordering; (c) ontologies were **verbalized** (triples → sentences)
rather than fed as raw OBO, so the model reads them as prose.

**Mid-training mix.** Domain-vs-general replay ratio is treated as a *hyperparameter to be swept*
({no-mid, 25/75, 60/40, 80/20}) rather than fixed; an expert committee (see §6) specifically
challenged an initial 25/75 default. Replay uses general corpora (FineWeb-Edu / The Stack /
Wikipedia) to mitigate catastrophic forgetting.

### 3.2 Grounded SFT data (11 task families)

Every SFT example is anchored to a real artifact. Task families and generators:

| Task | Grounding | What it teaches |
|---|---|---|
| `routing` | verified query→workflow labels | intent → workflow |
| `rag_routing` | retriever-mined candidates | pick gold from hard-negative candidate block |
| `param` | real parameter maps | flat parameter extraction |
| `cond_param` | full parameter schema | extract only user-specified/overridden params (few-valid restraint) |
| `wfgen` | workflow catalog | analysis-category generation |
| `decompose` | step metadata | phase→step DAG (hierarchical) |
| `interwf_decomp` | multi-domain samples | cross-workflow DAG (parallel/sequential) |
| `clarify` | required-param schema | ask for missing required param, do not hallucinate |
| `diag_fix` | real `real_exec_err` logs | `{category, root_cause, fix}` from execution traces |
| `autofix` | real errors | error → fix category |
| `protocol` | QC thresholds | pass/fail/warn checks |

Key anti-patterns avoided:
- **No target-description paraphrasing.** Routing queries are grounded in real studies and
  verified workflow runs, not reworded workflow blurbs.
- **Conditional-parameter restraint.** For long conditional schemas (often 8+ parameters), the
  gold extracts only the *few* the user actually specified or overrode from default (measured:
  8.2 shown → 1.4 gold on average). This teaches the model *not* to restate defaults.
- **Hierarchical decomposition.** Workflows have *phases* and *steps*; decomposition gold is a
  phase→step DAG with intra-phase sequencing and cross-phase dependencies (74% of examples were
  multi-phase), not a flat step list.
- **Abstention.** `clarify` examples teach the model to request a missing *required* parameter
  rather than fabricate a plausible value.

### 3.3 Paraphrase-diversity layer

An early version relied on **format jitter** — swapping fixed instruction fragments and delimiters
(e.g., `INPUT:` → `Request:`). This produces near-duplicates and, as the committee noted, risks
*format-specific* gains that do not transfer.

We replaced it with genuine **paraphrase augmentation**: each request is reworded into K≈5
variants sampled from a 10-voice persona/style bank — *terse shorthand, verbose lab-notebook,
non-native English, typo-noisy, jargon-heavy, Slack message, formal grant register,
buried-in-irrelevant-context, limited-computational-vocabulary, PI-dictation-run-on*. The
assistant target and any structured block (parameter schema, retrieved-candidate list) are held
**verbatim**; only the free-text request span is rewritten. Real execution-error logs are left
untouched (they are ground truth, not paraphrasable).

**Result:** 3,969 → **17,291** examples (+13,322 distinct, deduped rewrites; ~4.5× on the 2,982
paraphrasable rows). An implementation note: an initial run under-yielded (~1 variant/row)
because the per-call token budget truncated the JSON list of long paraphrases; raising the budget
recovered the intended multiplier.

---

## 4. Contrastive retriever

BioMate routes by first retrieving candidate workflows, then having the LLM select. The retriever
is therefore the ceiling on routing quality. We fine-tuned `BAAI/bge-small-en-v1.5` with
**InfoNCE (MultipleNegativesRankingLoss)**:

- **Anchor:** the researcher's query (with the BGE search prefix).
- **Positive:** the correct workflow's verbalized document.
- **Hard negatives:** the top candidates returned by the existing **hybrid TF-IDF + dense**
  retriever that are *not* the gold — i.e., precisely the workflows the current system confuses
  with the correct one.

Loss is cross-entropy over the cosine-similarity matrix with in-batch positives + explicit hard
negatives (temperature 1/0.05). We report recall on a held-out query split (390 queries), before
vs after training:

| Metric | Before | After | Δ |
|---|--:|--:|--:|
| recall@1 (random split) | 0.233 | **0.767** | +0.534 (3.3×) |
| recall@5 (random split) | 0.377 | **0.915** | +0.538 (2.4×) |

The random split leaks (the same workflow appears in train and test). On an honest **family holdout**
(562 queries for 169 workflows held out entirely, never seen in training) the numbers are lower but the
gain still generalizes:

| Metric (family holdout) | Before | After | Δ |
|---|--:|--:|--:|
| recall@1 | 0.244 | **0.399** | +0.155 |
| recall@5 | 0.374 | **0.694** | +0.320 |

So the contrastive lift is real and generalizes to unseen workflows (not memorization); absolute
unseen-workflow recall (0.40@1 / 0.69@5) is the honest floor, with production sitting between the two
splits since most catalog workflows do accrue training queries.

Training set: 2,206 queries → 4,412 (query, +gold, −hard) triplets. This was a *frugal proof* on
an 8.6 GB CPU box (batch 8, 2 hard negatives, 1 epoch); the GPU configuration (batch 32, 4 hard
negatives, 2–3 epochs) is expected to improve further.

**Why this matters for the LLM.** With recall@5 at 0.915, the retriever reliably places the gold
in the top-5, so the `rag_routing` candidate blocks presented to the LLM become genuinely *hard*
(the gold sits among its closest confusables). The LLM then learns to *disambiguate*, rather than
to compensate for a weak retriever. Knowledge (the catalog) stays in retrieval; skill
(disambiguation) goes into weights.

---

## 5. Evaluation methodology and a cautionary finding

### 5.1 The zero-delta artifact

An earlier 27B QLoRA SFT run trained correctly — training loss fell from 1.185 to 0.604 over 200
steps — yet the held-out evaluation reported a train-vs-base delta of **exactly 0.0 on every
benchmark**, including a *continuous* recall metric (parameter extraction) across 37 items. An
exact 0.0 on a continuous metric across many items is only possible if base and SFT produced
identical outputs for every item — i.e., the adapter was a **no-op at inference**, not that
training failed.

Root cause: the evaluation loaded the base once and toggled the adapter with
`disable_adapter()`; when the adapter has no effect at generation time (wrong path, quantization
mismatch, or a toggle that does not take), the harness silently reports "training didn't help."

### 5.2 Guard

We added a **startup logit probe**: the harness runs one forward pass with the adapter enabled
and one with it disabled, and *fails loudly* if the maximum absolute logit difference is below a
threshold — converting a silent, misleading zero into an explicit, diagnosable error. A per-item
"identical output fraction" warning backstops the aggregate. The canonical evaluation is a
**two-server comparison** (merge the adapter, serve merged and base independently under vLLM),
which removes adapter-toggle ambiguity entirely.

**Lesson.** For adapter-based fine-tuning, never trust a same-process enabled/disabled delta
without a positive control that the adapter changes logits at all.

---

## 6. Committee review

We convened a multi-LLM expert committee (an OpenAI model, a Google model, and a Claude model)
that first learned BioMate, then reviewed the preparation. Actioned items: (1) replace format
jitter with real paraphrase diversity (§3.3); (2) add cross-workflow decomposition and
abstention/negative examples; (3) treat the mid-training ratio as a swept hyperparameter, not a
fixed 25/75; (4) prioritize *retriever-first* improvements (§4); (5) add execution-trace
diagnosis with fixes (`diag_fix`). Deferred to the GPU stage: real if/then conditional parameters
mined from nf-core schemas, the mid-train ratio sweep, and grounded RL/DPO.

---

## 7. Two-model plan (small + ~27B) and dual deployment

We will train and compare two models from the same family (shared tokenizer and chat template) —
a small (~4B) and a large (~27B) — under a **controlled design: identical data, identical task
mix (all 11 tasks), identical prompts, holdout, and evaluation; the only variable is model
capacity.** We deliberately do *not* pre-assign tasks to a model; both are trained on the full 17k
enriched set and evaluated on every task.

The purpose is to measure, per task, how far the small model closes the gap to the large one. Any
deployment specialization is a **post-hoc conclusion from those per-task deltas**, not a design
input — for example, whether a **cascade** (the small model attempts each request and escalates to
the large model on low confidence or hard cases) is justified, or whether a single model suffices.
Both are trained with the identical pipeline (mid-train → merge → SFT → merge → eval → grounded RL)
and share the contrastive retriever. The two runs differ only in base checkpoint and
size-appropriate capacity knobs (LoRA rank and step budget).

---

## 8. Limitations and next steps

- **No end-to-end training numbers yet.** Mid-training, SFT on the enriched set, and RL require a
  GPU box; only the retriever (small enough for CPU) has final numbers here.
- **Retriever proof is under-scaled.** Local RAM (8.6 GB) forced a small batch and single epoch;
  the GPU run should exceed the reported recall.
- **RL is designed, not run.** The grounded reward (schema validity + execution success) and DPO
  pairing are specified; training is pending.
- **Real conditional if/then parameters** need an nf-core `nextflow_schema.json` fetch (only a
  handful are available locally).

Immediate next actions: (1) re-mine `rag_routing` with the contrastive retriever and re-fold;
(2) provision a GPU box and run the two-model pipeline with the mid-train ratio sweep and the
fixed evaluation; (3) implement grounded DPO.

---

## Appendix A — Artifact locations

- Enriched SFT: `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/sft/multitask_sft_enriched.jsonl`
- Base joint SFT: `.../sft/multitask_sft.jsonl`
- Mid-training corpus: `.../midtrain_corpus/*.jsonl`
- Contrastive retriever: `.../retriever/bge-routing-contrastive/`
- Generators & trainers: `evaluation/local_trial/` (see `train_retriever_contrastive.py`,
  `paraphrase_augment.py`, `midtrain_run.py`, `train_qlora_pilot.py`, `eval_holdout.py`,
  `build_rag_routing_sft.py`, and the per-task `generate_*.py` / `build_*.py`).

## Appendix B — Reproducibility notes

- Retriever `datasets`-free training loop avoids an `fsspec`/`s3fs` dependency conflict and ports
  cleanly to GPU.
- Data artifacts live in S3, not git (`docs/20260912_onprem_llm/midtrain_corpus/*.jsonl` and
  `routing_data_v1/*.jsonl` are gitignored); code is versioned on `integration/dev-test`.
