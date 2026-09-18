# Expert-committee review of the local-LLM training-data preparation

Committee: **Claude Opus 4.8** (me) + **gpt-5.6** (OpenAI API) + **gemini-3.8-flash** (Google API, latest),
each acting as a bioinformatics domain expert + a deep-learning/LLM-training expert. Briefed on BioMate,
then asked to review the prep (mix ratio, corpus, SFT, ROI, risks). Raw reviews: `/tmp/committee_openai.txt`,
`committee_reviews/gemini3.8flash_review.md`. Script: `evaluation/local_trial/committee.py`.

## Strong consensus (gpt-5.6 + gemini independently agreed)
1. **25% domain / 75% general is NOT justified — do not adopt as default.**
   - gemini: 80/20 (LoRA already resists forgetting → 75% replay is wasteful); gpt-5.6: 60/40.
   - BOTH: **sweep it** on a small proxy (Qwen 1.5B/7B): {no-mid, 25/75, 60/40, 80/20} at 200–300M
     tokens, identical SFT after; extend only a clear winner. Optimum = domain val-perplexity (Nextflow/
     JSON schemas) drops while general (MMLU/HumanEval) degrades <2–3%.
   - Also: our ~37M internal at 25% of a 2–4B run → repeating internal 14–27× = **catastrophic overfit**.
2. **Mid-training is the LOWEST-ROI step and contradicts our own principles.** Since knowledge → RAG and
   formats/skills → SFT, a big 2–4B mid-training run is largely "dead weight" and risks regressions.
   gpt-5.6: **"No-go without pilot evidence."** ROI ranking (both): **Retriever/RAG > SFT > RL > mid-training.**
3. **RAG-SFT is the critical missing piece (biggest risk = train/inference mismatch).** We plan RAG at
   inference but SFT on parametric knowledge. Every routing/decompose/param SFT example MUST be formatted
   as the **production RAG prompt** — include 2–3 retrieved relevant tools + 2–3 distractors — so the model
   learns to attend to and obey injected context, not parametric memory. Otherwise it ignores the retriever.
4. **SFT set is too small (1,834) and gapped.** Expand to ~15–30k verified, scenario/family-complete.
   Specific gaps both raised:
   - autofix (211) & protocol (49) **negligible** — need execution-trace-grounded 1,000+;
   - decomposition **intra-workflow only** → add **cross-workflow / vague cross-domain** DAGs;
   - **missing negatives / clarification / abstention** (param without required values → ask, not hallucinate);
   - preservation examples for the other ~22 tasks (avoid negative transfer).
5. **Corpus recompose:** downweight **Hetionet + raw KG + general PMC** (off-topic for a *tool/workflow*
   agent); **add EXECUTION LOGS/TRACES** (stdout/stderr/stack traces paired with code — essential for
   diagnosis/autofix, currently absent); use KG/ontologies to synthesize **graph-walks / reasoning paths /
   hard negatives**, not flat memorized triples.
6. **Evaluation:** use **workflow-family / tool-family / domain / temporal holdouts** (not random) +
   **blinded human review** for semantic cases (verifiers have blind spots: schema-valid ≠ correct;
   auditor shares model bias). Decontaminate held-outs from ALL stages.

## Concrete techniques the committee added (gemini-3.8-flash + gpt-5.6)
- **Inverse Execution Mining (fixes param yield ~16%):** stop unstructured synthesis; parse the 4,200
  VERIFIED workflows → extract the REAL parameter maps used → back-translate to the NL instruction that
  would produce them → 100% schema-valid pairs, zero rejection waste. (Also yields real DAGs for decomposition.)
- **Format Jittering (fixes format-overfit / the transfer finding):** train across 3 equivalent
  production templates with varied delimiters/whitespace/system-verbosity/tool-order + partial-context
  examples → robust context-reading, not memorized key sequences.
- **CLI `--help` ingestion:** scrape `--help`/manpages for tools → exact flags/params (better than KG trivia).
- **Schema-constrained RL/DPO reward:** R = α·I(valid JSON/schema) + β·tool-selection F1 + γ·I(Nextflow lint/preview passes)
  → preference pairs on failing param/autofix cases; targets production tasks with zero forgetting risk.
- **Mid-training, if kept:** ≤200–300M tokens, 60% bio-code/CLI/logs + 40% replay, targeting DSL syntax
  (Nextflow DSL2/WDL/CWL) only — a "warmup adapter", not broad adaptation.

## My (Claude) synthesis
The committee is right, and it materially revises our plan. We over-invested in mid-training + corpus
breadth and under-invested in the three things that actually move a private agentic assistant:
**(1) the retriever, (2) RAG-grounded SFT that mirrors production, (3) grounded RL.** Mid-training becomes
*conditional on a cheap ablation*, not the headline. The corpus's proprietary/task-proximal parts
(DB-as-KG, code, workflow-order, execution traces) matter; the generic biomedical KG (Hetionet) and raw
literature matter little for tool/workflow orchestration.

## Revised plan (committee-driven)
1. **Retriever/RAG first (highest ROI):** push precision@k + dynamic schema/tool-context injection on the
   existing hybrid retriever (recall@20=0.95). This is the engine.
2. **RAG-SFT (high):** regenerate ALL task SFT as production RAG prompts (retrieved relevant + distractor
   context); scenario/taxonomy coverage of the ~28 intents; add **negatives + clarification/abstention**;
   **cross-workflow decomposition**; scale to ~15–30k verified; family/temporal holdouts.
3. **Grounded RL (medium-high):** execution/schema reward → fixes param over-fills, autofix, chain-runs.
4. **Mid-training = CONDITIONAL:** 200–300M pilot, sweep {no-mid,25/75,60/40,80/20}; recomposed corpus
   (downweight Hetionet/KG/PMC; add execution traces; KG→reasoning-paths); extend only a proven winner.
5. **Add execution-trace corpus** (stdout/stderr/tracebacks ↔ code) for diagnosis/autofix + RL reward.
6. **Eval overhaul:** family/tool/temporal holdouts + blinded human review; decontaminate all stages.

## What this changes about what we built
- The ~37M mid-training corpus stays *staged and useful* (esp. DB-as-KG, code, workflow-order) but is
  **demoted** from "the plan" to "a conditional pilot ingredient"; Hetionet/raw-KG/PMC get downweighted.
- The SFT set is the **new priority**, but must be **rebuilt as RAG-SFT** (context-grounded) + scaled +
  gap-filled (negatives, clarification, cross-workflow, execution traces) — not just balanced.
- **Retriever + execution-trace harvesting** move to the front.
