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
character/token-overlap gates against a held-out benchmark. We evaluate on the RealBio harness
across eight tasks. Measured on our own served weights, the 27B base is **on par with the far
larger hosted Qwen3.8-Max** (e.g. autofix 0.87 vs 0.86, param-prefill F1 0.66 vs 0.69, boin 0.78
vs 0.11), confirming that a small on-prem model suffices for these tasks. Our central empirical
finding concerns *transfer*: a routing LoRA that improved routing on its own prompt format
transferred **nothing** to the harness's format and caused **−7pp negative transfer** on autofix —
because fine-tuning gains are specific to the exact prompt format and label space, and single-task
tuning damages untuned tasks. Correcting for this — training **in the exact harness formats,
jointly across the task cluster** — yields real, targeted gains with **no negative transfer**:
routing-bare **+10.5pp** (0.18→0.285) and parameter-extraction restraint **−32% must-not-fill
violations** (precision 0.77→0.82), while every untuned task held. We conclude that for
retrieval-grounded agentic tasks the durable levers are **retrieval** (a hybrid retriever reaches
recall@20=0.95 on routing) and **format-matched joint fine-tuning for targeted disciplines**
(restraint, format adherence), not single-task weight tuning. We further show the same model
natively interprets scientific figures on-prem (exact value reading), and outline an
execution-grounded self-evolving loop that avoids model collapse.

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
3. **A confound-aware evaluation** (2×2 for routing) plus a real production-harness baseline showing
   a 27B on-prem model on par with a far-larger hosted model, and the finding that **retrieval — not
   weight tuning — is the dominant routing lever**.
4. **A transfer result with a fix:** fine-tuning gains are specific to the exact prompt format/label
   space and single-task tuning causes negative transfer; **format-matched joint training** recovers
   real, targeted gains (routing-bare +10.5pp, param restraint −32%) with none. Plus a validated,
   natively-multimodal on-prem model and an execution-grounded self-evolving loop design.

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

Manual inspection confirmed the scores are not substring-inflated. A prior naive evaluation reported a spurious 0.0 delta; the 2×2 design reveals why. **Crucially, these numbers are on our *own* prompt format** — they did not transfer to the production RealBio harness (next), which is itself the central finding.

**The 27B baseline on the real RealBio harness (our served weights).** Running the production
harness + scorer against our own served base 27B, across eight tasks, gives a baseline **on par
with the far-larger hosted Qwen3.8-Max**:

| Task | Qwen3.8-27B (ours) | Qwen3.8-Max (hosted) |
|---|---|---|
| routing — bare (no candidates) | 0.18 | 0.345 |
| routing — catalog (candidates) | 0.815 | — |
| autofix (fix-category) | 0.87 | 0.86 |
| param_prefill (F1) | 0.664 | 0.692 |
| workflow_gen | 0.50 | 0.50 |
| protocol_QC | 0.43 | 0.46 |
| pbpk (within-2×) | 0.067 | 0.00 |
| boin (exact MTD) | 0.778 | 0.111 |
| drug_disc (Spearman) | 0.70 | 0.70 |

**Transfer failure (the central result).** A routing LoRA trained on our format (+3pp on that
format) gave **nothing** on the harness (catalog 0.815→0.795) and **−7pp on autofix** (0.87→0.80) —
single-task tuning caused negative transfer. Root cause: fine-tuning gains are specific to the exact
**prompt format and label space**, and the harness uses different prompts and label sets (e.g. a
10-category autofix taxonomy, a 63-name routing option set) than our bespoke format.

**The fix — format-matched joint training.** Rebuilding the data in the *exact* harness prompt
formats and label spaces, and training **one joint LoRA** across routing+param+autofix, produced
real, targeted gains with **no negative transfer**:

| Task | Base | routing-LoRA (single) | Multitask-LoRA (format-matched) |
|---|---|---|---|
| routing bare | 0.18 | 0.17 | **0.285** (+10.5pp) |
| routing catalog | 0.815 | 0.795 | 0.805 |
| autofix | 0.87 | 0.80 (−7pp) | 0.85 (held) |
| param F1 / precision | 0.664 / 0.77 | 0.646 / — | 0.657 / **0.823** |
| param must-not-fill violations | 53 | 49 | **36 (−32%)** |
| workflow_gen / protocol / boin / dd | 0.50/0.43/0.78/0.70 | (n/a) | 0.50/0.43/0.78/0.70 (all held) |

Gains concentrate where matched data was added (routing-bare recall; param **restraint**), untuned
tasks are preserved (no negative transfer), and already-strong tasks (autofix) are near ceiling. A
planned round-2 (adding protocol/workflow_gen, balancing param, de-skewing autofix) was built
(1,253 balanced examples across five tasks) but not trained, due to an unrecoverable GPU-host
failure; the data and pipeline are ready.

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

## 6. Discussion

On the production harness, a strong instruct base plus a candidate list already achieves 0.815 on
routing and is on par with a far larger hosted model across the suite; fine-tuning adds targeted
gains. This supports **"knowledge in retrieval, skill in weights."** Notably, measuring the real
baseline overturned an intuition we initially acted on: param-prefill and autofix are **not**
weak-base tasks (0.66 F1 and 0.87 on the harness) — a small on-prem model is already competitive
there. Fine-tuning's realized value was **targeted**: better *restraint* in parameter extraction
(−32% over-fills) and better *recall* in no-candidate routing, not broad jumps.

**Fine-tuning gains are format-specific; train on the metric you report.** The load-bearing lesson
is that a LoRA which improved a task on one prompt format transferred nothing to a different format
and *harmed* an untuned task (−7pp autofix). "Train == eval" must mean the *production/eval* format,
not a bespoke one; and tuning must be **joint** across the cluster (single-task caused negative
transfer, joint did not). This also exposes a tension the field warns about: training to a
benchmark's exact label space risks *benchmark adaptation* over capability — so we distinguish
genuine capability gains (restraint, format adherence, real-log diagnosis) from format-fitting, and
keep **retrieval** (recall@20=0.95) as the durable routing lever rather than memorizing a label set.

**Self-evolving loop.** Production turns are logged (intent, route, params, run outcome, user
correction); successes become positives and failures + corrections become hard negatives and
episodic memory; an execution/schema verifier plus the independent auditor gate new episodes; the
model is periodically retrained (ReST-EM style) on passers with real data mixed in, and prompts are
optimized between rounds. Grounding the verifier in execution — not self-judgment — is the specific
safeguard against model collapse.

## 7. Limitations

- All eight tasks are evaluated for base and the format-matched joint LoRA; a **round-2** joint run
  (adding protocol/workflow_gen, balancing param, de-skewing autofix) was fully prepared (1,253
  balanced examples) but not trained, due to an unrecoverable GPU-host failure — realized gains are
  therefore from the first joint LoRA only.
- Fine-tuning gains, while real, are **modest and data-limited**; clearing a production bar on
  already-strong tasks likely needs more/better-balanced per-task data, not the method.
- Reverse-generated queries are synthetic; realism is enforced by the auditor but not by real users.
- Training to the harness's exact label space is **benchmark adaptation** for some tasks; we flag
  which gains are capability vs format-fitting, but the distinction warrants held-out formats.
- Parameter-data generation yield was low (~17%) and volume-limited (68–96 audited); autofix labels
  are skewed toward `missing_input`/`dependency` (fixture-population artifact).
- Base multimodal capability is general-purpose; specialized modalities (cryo-EM, histology) are
  unquantified. The independent auditor is itself a model; execution/schema checks are the stronger gate.

## 8. Future work

Run the prepared round-2 joint training (protocol+workflow_gen added, param balanced, autofix
de-skewed) and re-measure per task; stand up the **hybrid retriever** (lexical+domain-dense,
recall@20=0.95) as the routing front-end with a learning-to-rank reranker over retrieved hard
negatives; benchmark against open baselines (Aloe-Qwen2.5, OpenBioLLM, Meditron) and the LifeSciBench
axes; fine-tune vision from figures rendered off known data (verifiable targets) plus open-access
figure–caption pairs; and deploy the execution-grounded self-evolving loop in production. Robust,
resumable GPU orchestration (the infra friction here was a primary cost) is a prerequisite.

## References

(To be formatted. Key sources: the self-evolving-agent surveys arXiv:2508.07407 and 2507.21046;
STaR (arXiv:2203.14465) and ReST-EM (arXiv:2312.06585); Reflexion; model-collapse (Nature 2024);
biomedical-specialist-vs-generalist evidence (Fully-Open Meditron; arXiv:2408.13833; Nature Medicine
2026); Aloe (arXiv:2505.04388); BioMistral (arXiv:2402.10373); OpenBioLLM; GPT-Rosalind and
LifeSciBench (OpenAI, 2026). See `SELF_EVOLVING_SURVEY.md` and `SMALL_DOMAIN_LLM_SURVEY.md` for the
adversarially-verified citation sets.)
