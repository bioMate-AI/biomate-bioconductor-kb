# SFT train/test data audit + the unified grounded/contrastive rebuild recipe (2026-09-29)

Audit of `multitask_sft_enriched.jsonl` (62,397 rows) against the FULL enriched catalog (4,172 workflows,
11,481 tools) + the code-grounded action taxonomy. Every number below is measured this session.

## What the audit found

### Diversity is GOOD (not the problem)
- 95.1% unique user prompts (3,074 dup), 98.5% distinct answer templates, ~0% mangled-name templates.
- BUT the aggregate hides **per-task surface-form templating**. Low-diversity tasks (opening-6gram uniqueness):
  - `out_of_catalog_composition` **0.2%** (100% share one fixed instruction opening) — worst
  - `autofix_repair` 45%, `model_selection` 50%, `design_constraint` 54%, `dataset_prerequisite_check` 64%
  - `task_decomposition` 55% — but its repetition is a **claude-log scaffold artifact**
    ("adversarial claim verifier voter 3 3") = a *filtering* problem, not paraphrasing
  - Already-diverse (leave alone): knowledge_recall 92%, workflow_routing 86%, param_extraction 91%,
    lane_arbitration 98%, tool_recommendation 87%, multi_workflow_chaining 99%.

### The real disease: routing SFT is CLOSED-BOOK
- The routing training prompt has **no candidate list** → the model must MEMORIZE which of 4,172 names to
  emit from the request alone. This single choice causes all three measured defects:
  - **Hallucination** ~10–20% of routing targets (exact number unmeasurable by string-match because of the
    next defect; consistent with the root-cause doc's 28%).
  - **Upgrade-fragility** — a renamed/upgraded tool breaks the model (name lives in weights).
  - **Sibling confusion** — no candidates to discriminate against.
- **D3 (no output contract):** routing answers phrase the target inconsistently ("run \`X\`" vs "Yes, RCy3 is
  suitable…" vs "route your data to…") → hurts grading AND learning.
- A **catalog-coverage tail**: some "hallucinations" are real tools missing from our index (mOTUs,
  FusionCatcher, Pairtools) — fix the catalog, not (only) the data.

### Task-taxonomy coverage gap (vs code-grounded action surface)
Authoritative taxonomy (from `backend/lib/galaxy/ai/agents/unified_intent_router.py` `UserIntent`, 10 intents
+ MCP tools + `data_sources.py`): workflow_generation, research_question, tool_search, tool_recommendation,
result_comparison, conclusion_drawing, benchmark_query, literature_survey, parameter_help, general_question,
+ query_database (20 sources), resolve_accession, chains (curated + prototype typed-port planner).
- **No first-class SFT tasks** for literature/patent/DB search. Keyword presence only: literature 3,590,
  db 1,710, patent **139**, chain 1,293, auto-gen 21.
- **patent_search DOES NOT EXIST in code** (only DPO/data-source refs) → do NOT train a capability we can't
  serve; either build the retriever first or drop it.
- **auto-generate-from-scratch DOES NOT EXIST** — it's template + param-fill. Train "compose from existing",
  not "write a novel Nextflow file".

## The unified rebuild recipe (composes every fix)

| layer | fixes | mechanism | status |
|---|---|---|---|
| grounded-by-construction | hallucination | generate FROM db, validate every name → drop/repair | designed (D1) |
| **open-book candidate-grounded** | memorization, **upgrade-fragility**, contract | prompt = request + retrieved candidates; target = exact name copied from list | **built** `routing_openbook_sft.jsonl` (2,981) |
| **contrastive DPO** | sibling confusion, hallucination, exact-spelling | chosen=gold; rejected = hardest same-domain sibling / mangled-spelling / off-catalog | **built** `routing_dpo_pairs_v2.jsonl` (8,943 = 3×2,981) |
| paraphrase (positives) | surface templating | rewrite request into K persona voices; preserve entities+gold; hard-verify | **built** `build_paraphrase_v2.py` (targets low-div tasks) |
| retriever contrastive | candidate quality (upstream) | InfoNCE + hard negatives on the dense lane arbiter | designed |

Contrastive and paraphrase COMPOSE: paraphrases are the positives; siblings/hallucinations are the negatives.
Hard-negative example produced: chosen `milor_da_contrasts` vs rejected `milor_da_glmm_random_effects` (same
family, different method) — the exact confusable boundary. All contrastive data is **deterministic, zero-LLM**
(mined from the catalog), so a tool upgrade = re-mine, no retrain.

### Training order
1. SFT on {existing multitask ∪ open-book routing ∪ paraphrase-augmented low-div tasks}.
2. DPO/ORPO on the 8,943 hard-negative pairs (after SFT).
3. (upstream, separate) retriever contrastive fine-tune → better candidate lists lift everything.

## Artifacts (this session)
- `evaluation/local_trial/build_contrastive.py` → `s3://…/sft/routing_openbook_sft.jsonl`,
  `routing_dpo_pairs_v2.jsonl`
- `evaluation/local_trial/build_paraphrase_v2.py` (role-aware, entity-preservation verified)
- v1 mid-train running (`full_v1strong`, L4) — corpus now includes PMC full-text (63M v1) + tool-docs +
  DB-catalog + de-degenerated KG (×1) + dedup/quality filter.

## Task-aware mid-train (v2) — design the mid-train toward the ultimate goal

Root cause D4: v1-style mid-train is next-token LM on flat text; it raised perplexity but transferred
nothing (degenerate KG hurt most). Fix = **instruction / task-aware continued pre-training** (cf. Cheng et
al. 2024, *Instruction Pre-Training*): convert the corpus into task-structured examples so the objective
rehearses the goal skills. **Division of labor** (also resolves the tool-upgrade question):

- **mid-train (task-aware) = STABLE, transferable knowledge + reasoning** → OK in weights:
  - `kg_multihop`: verbalized KG triples → entity adjacency → **2-hop reasoning QA** ("through which
    intermediate is A connected to C, by what relations?") — *uses* the graph vs memorizing flat triples.
  - `tooldoc_qa`: catalog tool/workflow fields → usage/param knowledge QA.
  - `lit_extract` (LLM, sampled): abstract → method/organism/finding extraction QA.
- **SFT+DPO+retrieval = VOLATILE catalog selection** (routing/tool/chain) → NOT in weights (re-mine on
  upgrade). This is `build_contrastive.py` (open-book + hard-negative DPO).

Generator: `evaluation/local_trial/build_instruction_midtrain.py` (+ `build_instmid.sh` box runner →
`s3://…/midtrain_corpus/instruction_midtrain.jsonl`). Targets ~250k KG-reasoning + 60k tool-QA + 40k
lit-extraction. **v1 = raw-text baseline** (running now); **v2 = task-aware** — measures whether aligning the
mid-train objective to the goal makes mid-train finally *help* (v1 tests whether dedup+KG-balance stopped the
bleeding; v2 tests whether task-alignment reverses it).

## Open / next
- Run paraphrase-v2 on low-diversity tasks; assemble v5 SFT; wire DPO stage; re-eval routing (candidate-
  grounded, deployment mode).
- PMC full-text scale: E-utils caps ~10k articles even with WebEnv → v2 needs the PMC OA **bulk tarballs**.
- Filter the `task_decomposition` claude-log scaffold artifacts.
- Add first-class literature_survey / query_database / resolve_accession / chain tasks (grounded to the real
  handlers); skip patent until it exists in code.
