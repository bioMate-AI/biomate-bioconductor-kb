# Grounded, Leakage-Controlled Fine-Tuning of an On-Premises Multimodal LLM for Agentic Bioinformatics Workflow Orchestration

*Draft manuscript — BioMate on-prem LLM project. Status: living document; results filled as experiments complete.*

**Authors:** (TBD) · **Affiliation:** BioMate · **Correspondence:** (TBD)

---

## Abstract

Cloud LLMs power most agentic bioinformatics assistants, but on-premises deployment is required
for data-sovereign labs and cost control. We study whether a general, natively-multimodal
instruct model (Qwen ~27B) can be specialized on-prem, via parameter-efficient fine-tuning
(QLoRA), for the *structured, retrieval-grounded* tasks that dominate a production assistant
(BioMate): intent classification, workflow routing over a 4,200-entry catalog, schema-grounded
parameter extraction, error diagnosis, and parsed-output interpretation. Our central
methodological contribution is a **grounded, leakage-controlled data-generation pipeline**:
queries are *reverse-generated* from real database artifacts (workflow input/tool metadata,
parameter schemas, execution logs) rather than paraphrased from target descriptions, then
filtered by deterministic schema/execution checks, an **independent-model auditor**, and
character/token-overlap gates against a held-out benchmark. Our central empirical contribution is
a **2×2 evaluation design** ({base, SFT} × {no-candidates, with-candidates}) that disentangles
retrieval/candidate-context effects from true fine-tuning lift. On held-out routing, providing
the candidate list raises a strong base model from 0.13 → 0.96 accuracy (**+0.83**, the dominant
factor), while fine-tuning adds a small but statistically significant **+0.03** (0.96 → 0.99,
95% CI [0.005, 0.06]) concentrated on confusable same-domain cases. We argue this "knowledge in
retrieval, skill in weights" result — consistent with the design of closed frontier life-science
models — implies that fine-tuning budget should target *weak-base* tasks (parameter extraction,
autofix), not routing. We further show the same model natively interprets scientific figures
on-prem (exact value reading), and outline an execution-grounded self-evolving loop that avoids
model collapse.

---

## 1. Introduction

Agentic assistants for bioinformatics translate natural-language intent into executable analyses:
selecting workflows, extracting parameters, diagnosing failures, and interpreting outputs. In
production (BioMate), these are served by an ensemble of cloud LLM calls across ~28 distinct
tasks. On-premises operation is increasingly required — for institutions that cannot send data to
third parties, and to bound inference cost — but it raises the question of *what, if anything,
must be trained* into a local model versus supplied at inference.

We make four contributions:
1. **A task-grounded map** of every LLM call in a production bioinformatics assistant (28 tasks),
   partitioned into structured (classify/select/extract), generative, and knowledge tasks, with
   a per-task verifier.
2. **A grounded, leakage-controlled data-generation pipeline** that reverse-generates training
   queries from real DB artifacts and verifies them with deterministic checks + an independent
   auditor + overlap gates — designed to avoid the circularity and train/test leakage that
   invalidate naive synthetic pipelines.
3. **A confound-aware 2×2 evaluation** that separates the effect of in-context retrieval from the
   effect of fine-tuning, and an honest finding that retrieval dominates for routing.
4. **A blueprint** for a single jointly-trained multi-task, natively-multimodal on-prem model and
   an execution-grounded self-evolving improvement loop.

## 2. Related work

**Instruction-data generation.** Self-Instruct, Alpaca, Evol-Instruct/WizardLM, Orca, Magpie, and
Humpback generate SFT data by prompting a teacher; APIGen-MT grounds generation in real artifacts
with multi-stage verification. Our pipeline follows the grounded/verified branch and adds explicit
anti-circularity (never paraphrase the target's own description) and overlap gating.

**Self-evolving agents.** Two 2025 surveys unify the field (what/when/how to evolve). The
STaR/ReST-EM loop (generate → filter by correctness → fine-tune → repeat) reliably beats
human-data-only SFT; Reflexion adds inference-time gains via episodic memory. The dominant risk is
**model collapse** from training on self-generated data (a universal property of learned generative
models), mitigated by grounding the verifier in real logs/execution rather than self-judgment.

**Biomedical LLMs.** Domain-specialized models (BioMistral, OpenBioLLM, Meditron, Aloe, HuatuoGPT)
frequently *fail to beat their generalist base* on contamination-controlled data, and for
retrieval-grounded tasks in-context retrieval tends to beat parametric domain fine-tuning. Genomics
/ single-cell foundation models (Evo2, DNABERT-2, scGPT, Geneformer) are sequence/embedding models
with no natural-language interface — tools an agent calls, not reasoning cores.

**Frontier life-science models.** Closed models such as GPT-Rosalind are reported to be trained on
~50 common biological workflows and to interface with public databases, with "skepticism tuning"
for hallucination — i.e., *skill in weights, knowledge in retrieval, grounding for safety*. Our
design mirrors this with open weights. LifeSciBench (750 expert tasks across seven workflow areas)
provides an evaluation north-star. **Gap:** no open, agentic LLM orchestrates bioinformatics
*workflows* over a real tool catalog with grounded, leakage-controlled data and execution-verified
self-improvement — the niche this work occupies.

## 3. System and tasks

BioMate exposes 4,200 workflows across 36 domains and 12,312 tools with rich metadata
(input/output types, tools used, parameter schemas, scientific context, execution status/errors).
An audit of the codebase identified **28 LLM-backed tasks (T01–T28)**. We target the **structured,
verifiable, high-frequency cluster**: intent classification (T01), domain inference (T03), workflow
routing (T05), schema-grounded parameter resolution (T06), workflow-modification classification
(T10), log diagnosis (T18), autofix/QC remediation (T19), and parsed-output interpretation (T20).

**Design principle — skill in weights, knowledge in retrieval.** Volatile knowledge (which
workflows exist, their schemas, biology facts) is supplied at inference via retrieval; the model is
trained on the transferable *skill* of operating over that retrieved context. This keeps the model
robust to catalog change and is consistent with both the biomedical-LLM evidence and the design of
frontier life-science models.

## 4. Methods

**Grounded reverse-generation.** For each task we ground generation in real DB artifacts, never in
the target's own description (anti-circularity):
- *Routing (T05):* query reverse-generated from a workflow's real `input_types`/`tools_used`/
  `output_types` + a sampled researcher persona; supplemented with real GEO study descriptions
  whose assay type deterministically labels the pipeline.
- *Parameters (T06):* schema-valid parameter values are *sampled* from a workflow's
  `params_schema`, then a query is generated to *imply* them without naming keys (APIGen-style); the
  gold extraction is schema-valid by construction, and distractor parameters test restraint.
- *Diagnosis/autofix (T18/T19):* grounded in real `real_exec_err` logs.

**Verification (multi-stage, grounded).**
1. *Deterministic gates:* schema membership (routing candidate contains the answer; extracted
   values legal vs `allowed_values`/type), a name-leak guard, and character/token-3gram + substring
   overlap against the held-out benchmark (<0.5 similarity required).
2. *Independent auditor:* a **different model** than the generator scores realism, correctness,
   non-circularity, and restraint; only unanimous passes are kept. For execution-verifiable tasks
   the deterministic check is authoritative.

**Anti-leakage.** Every training source is overlap-checked against the held-out RealBio benchmark;
observed maxima ≤ 0.24 (routing generated and GEO), well below the 0.5 gate.

**Training.** QLoRA (4-bit NF4, r=16, all projection modules, assistant-token-only loss) on the
Qwen base, on instance-store NVMe (L40S 48 GB). A shared prompt module makes the training and
evaluation protocols byte-identical.

**Evaluation — the 2×2 design.** For tasks with a candidate-context confound (routing), we evaluate
{base, SFT} × {starved (no candidates), in-format (candidates given)} and report paired bootstrap
95% CIs, logging every raw output. This isolates (a) the candidate/retrieval effect from (b) the
true fine-tuning lift — a distinction a single-condition eval cannot make.

**Multimodal serving.** The base is natively multimodal (a vision tower co-resident with the
language model). Text tasks run text-only (with the LoRA on the language layers); figure
interpretation (T17) is served by the same checkpoint with the vision tower enabled — the LoRA
rides on the language layers untouched.

## 5. Experiments and results

**Data.** Reverse-generation over the full catalog yielded, after auditing, **1,352 routing
examples spanning 1,119 distinct workflow labels** across 23 domains (versus 15 labels from GEO
alone), plus 1,244 real GEO episodes. All sources passed the overlap gate (max 0.24 vs RealBio).

**Routing 2×2 (200 held-out RealBio items).**

| | starved (no candidates) | in-format (candidates) |
|---|---|---|
| base | 0.13 | **0.96** |
| SFT  | 0.06 | **0.99** |

- Candidate/retrieval effect (base): **+0.83**, 95% CI [0.78, 0.88].
- True SFT lift (in-format): **+0.03**, 95% CI [0.005, 0.06] — small, significant; the 7 corrected
  cases are confusable same-domain workflows.
- The SFT model *regressed* in the starved condition (0.13 → 0.06), emitting descriptive rather
  than canonical names — a specialization/narrowing effect from training to select-from-candidates.

Manual inspection confirmed the scores are not substring-inflated. A prior naive evaluation reported a spurious 0.0 delta; the 2×2 design reveals why.

**Routing is retrieve-then-rank (not classification).** Reframing routing as a two-step search→rank problem, we measured the retriever directly over the full 4,200 catalog (196 in-catalog RealBio queries): hybrid **recall@20=0.94, recall@50=0.985**, but **recall@1 only 0.51**. Lexical TF-IDF (r@5=0.80) *beat* a general dense embedder (MiniLM, r@5=0.64) — domain routing hinges on rare tokens (gene/assay/tool names) a generic embedder blurs; a domain embedder or lexical is required. This shows the 2×2 candidate-context effect (+0.83) was the retrieval step, and that the ranker's real job is reranking a small set of *retrieved hard negatives* to lift recall@20→top-1. Consequently we model routing as learning-to-rank with graded relevance (not single-label), report recall@k separately from NDCG/top-1, and generate candidates from the real retriever rather than randomly.

**Vision (T17).** With the vision tower enabled, the same on-prem model read a controlled figure
exactly — recovering the title, axis label, all four values, and the correct highest/lowest
samples — demonstrating on-prem figure interpretation with exact value reading, without a separate
model.

**Parameter extraction (T06).** A pilot validated the APIGen-style pipeline: 47 generated episodes
→ **27 audited PASS (57%)**, with gold extractions schema-valid by construction and samples
faithfully grounded (e.g., "shotgun LC-MS/MS of trypsin-digested lysate" → `addCarbamidomethyl=true`).
Two limitations surfaced. First, *enum* parameters are the cleanest extraction targets, whereas
*boolean-false defaults* are weakly impliable (a query rarely states "not X") — scaling should
prioritize enums and explicitly-stated booleans/numerics. Second, generation yield was low (47/200
sampled) under concurrent teacher calls, indicating a need for retry-hardening before scale-up. A
schema-checked base-vs-SFT extraction eval is planned once the set is scaled.

**Log diagnosis (T18).** Grounding in real execution logs yields the highest data quality of any
task: 253 generated → **244 audited PASS (96%)**. Because each item is anchored to a real error log
that frequently states its own cause, the generated {category, root_cause, fix} is faithful and the
independent auditor confirms it (e.g., `'newBiodb' is not an exported object` → `dependency_error`;
`readRDS: unknown input format` → `wrong_format`). This supports a general principle: **the more the
task is grounded in real execution artifacts, the higher the achievable label quality** (routing
35% → param 57% → diagnosis 96% first-pass auditor rate). The category distribution is skewed toward
`missing_input`/`dependency_error` (reflecting the fixture-run failure population), which balancing
must account for at training time; production-log ingestion will broaden it.

**Multi-task joint training.** [Planned: one LoRA over the structured cluster with a task-balanced
mixture and per-task evaluation, including free-form examples to prevent the narrowing observed
above.]

## 6. Discussion

For retrieval-grounded routing, a strong instruct base plus a candidate list already achieves 0.96;
fine-tuning adds a small, real gain on hard cases. This supports **"knowledge in retrieval, skill
in weights"** and implies that fine-tuning effort should be re-allocated to tasks where the base is
weak (schema-grounded parameter extraction, autofix, output interpretation, and restraint) rather
than to routing. The specialization regression we observed is a concrete argument for *joint*
multi-task training with format diversity, over per-task adapters trained in isolation.

**Self-evolving loop.** Production turns are logged (intent, route, params, run outcome, user
correction); successes become positives and failures + corrections become hard negatives and
episodic memory; an execution/schema verifier plus the independent auditor gate new episodes; the
model is periodically retrained (ReST-EM style) on passers with real data mixed in, and prompts are
optimized between rounds. Grounding the verifier in execution — not self-judgment — is the specific
safeguard against model collapse.

## 7. Limitations

- Only routing is fully evaluated to date; multi-task results are pending.
- Reverse-generated queries are synthetic; realism is enforced by the auditor but not by real users.
- The label distribution is transcriptomics-skewed, mirroring the catalog.
- Base multimodal capability is general-purpose; performance on specialized modalities (cryo-EM,
  histology) is unquantified.
- The independent auditor is itself a model; execution/schema checks are the stronger gate where
  available.

## 8. Future work

Complete the structured-cluster data (T01/T06/T18/T19/T20) with grounded verifiers; run one joint
multi-task training and per-task evaluation against RealBio and the LifeSciBench axes, with open
baselines (Aloe-Qwen2.5, OpenBioLLM, Meditron); benchmark and, if needed, fine-tune vision using
figures rendered from known data (verifiable interpretation targets) plus open-access figure–caption
pairs; and deploy the execution-grounded self-evolving loop in production.

## References

(To be formatted. Key sources: the self-evolving-agent surveys arXiv:2508.07407 and 2507.21046;
STaR (arXiv:2203.14465) and ReST-EM (arXiv:2312.06585); Reflexion; model-collapse (Nature 2024);
biomedical-specialist-vs-generalist evidence (Fully-Open Meditron; arXiv:2408.13833; Nature Medicine
2026); Aloe (arXiv:2505.04388); BioMistral (arXiv:2402.10373); OpenBioLLM; GPT-Rosalind and
LifeSciBench (OpenAI, 2026). See `SELF_EVOLVING_SURVEY.md` and `SMALL_DOMAIN_LLM_SURVEY.md` for the
adversarially-verified citation sets.)
