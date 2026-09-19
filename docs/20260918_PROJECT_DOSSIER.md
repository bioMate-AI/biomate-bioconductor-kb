# On-Prem BioMate LLM — Project Dossier (for review)

**2026-09-19.** Single navigable index of everything: goal, data, tasks, code, documents, metrics,
data-quality history, and open items. Everything doable without a GPU is complete; artifacts are in S3,
code on branch `integration/dev-test`.

---

## 1. Goal & design
Private, on-prem LLM for BioMate (bioinformatics workflow assistant) driven by **data sovereignty**
(air-gapped / cannot use cloud APIs). Must be capable across BioMate's ~28 LLM tasks and generalize.

**Recipe:** open base → domain **mid-training** (continued pretraining) → multi-task **SFT** →
grounded **RL/DPO**, plus a **contrastively-trained retriever** as the routing front-end.

**Two-model controlled comparison:** `Qwen3.8-4B` and `Qwen3.8-27B` trained on the *identical* data and
all tasks; capacity is the only variable. Any role split / cascade is a POST-HOC conclusion.

---

## 2. Data

### 2.1 Mid-training corpus — **~44.5M deduped tokens** (`S3 …/20260912/midtrain_corpus/`)
| shard | ~tokens | preprocessing |
|---|--:|---|
| code_corpus | 17.2M | workflow scripts (Nextflow etc.) |
| tools_corpus | 16.7M | **tools DB, per-field**: rawText prose; help_text & scientific_context & parameters are JSON → **verbalized**; htmlContent dropped (99% redundant); Galaxy-page HTML stripped |
| chebi/go/hpo/edam/so | ~7.9M | ontologies verbalized (triples→sentences) |
| gtn_corpus | 1.6M | Galaxy Training Network tutorials |
| hetionet/db_kg/workflow_order | ~1.7M | KG edges + step-order verbalized |

Deduped via exact + (box) MinHash. `internal_corpus` (old raw-JSON extraction) superseded/excluded.
Still small vs domain norms (Meditron ~48B) → **corpus expansion suite** ready for the box (§5).

### 2.2 SFT — **15,254 validated examples, 11 tasks** (`S3 …/sft/multitask_sft_enriched.jsonl`)
Built grounded → paraphrase-augmented (3,969→~17,300) → **validation gate** (`validate_sft.py`) → 15,254.

| task | n | teaches |
|---|--:|---|
| rag_routing | 4,244 | pick workflow from retrieved (hard-negative) candidates |
| routing | 2,538 | intent → workflow (tool name NOT in request, by design) |
| param | 1,886 | extract implied params |
| decompose | 1,536 | phase→step DAG |
| wfgen | 1,531 | analysis-category generation |
| clarify | 1,266 | ask for missing required param (abstain, don't hallucinate) |
| cond_param | 1,042 | full schema shown → extract only specified (restraint) |
| diag_fix | 494 | execution error → {category, root_cause, fix} |
| interwf_decomp | 354 | cross-workflow DAG (parallel/sequential) |
| autofix | 211 | error → fix category |
| protocol | 152 | pass/fail/warn threshold checks |

Provenance: `…/sft/multitask_sft_enriched_preclean.jsonl` (pre-validation).

### 2.3 Retriever (`S3 …/retriever/bge-routing-contrastive/`)
BGE fine-tuned with InfoNCE on (query, +gold, −hard negatives). Random-split recall@1 0.23→0.77
(**leaky**); **family-holdout re-eval in progress** for the honest number (§4).

---

## 3. Task inventory & grounding principles
- **Grounded in real artifacts** — verified workflow runs, real `params_schema`, real `real_exec_err`.
  Never paraphrase the target's own description.
- **Request never names the target workflow** (routing/rag_routing) → forces task-understanding, not
  lexical matching. (So gold name absent from request is expected, not a defect.)
- **Param restraint** — extract only user-specified/overridden values; never restate defaults.
- **Hierarchical decomposition** — phase→step DAG with deps; cross-workflow DAG for multi-goal.
- **Abstention** — clarify when a required param is missing.
- **Diversity** — 10-voice persona paraphrase layer (gold + structured blocks verbatim).

---

## 4. Current metrics
- Corpus: 44.5M deduped tokens (11 shards).
- SFT: 15,254 validated / 11 tasks.
- Retriever: random-split recall@1 0.233→0.767, @5 0.377→0.915 (leaky); **family-holdout: BEFORE
  0.244/0.374, AFTER = _pending_** (honest generalization number).
- Prior 27B QLoRA SFT (old data): trained fine (loss 1.19→0.60); eval was a 0.0-delta ARTIFACT (fixed).

---

## 5. Code inventory (`evaluation/local_trial/`)
**Data generators (grounded):** `generate_routing_data`, `generate_param_data`, `generate_conditional_param`,
`generate_wfgen`, `generate_decomposition_data`, `generate_interworkflow_decomp`, `generate_clarification`,
`generate_diagnosis_fix`, `generate_autofix_harness`, `generate_protocol`, `build_rag_routing_sft`.
**Quality/validation:** `schema_guard` (param type/enum/genome guard), `validate_sft` (pre-train gate),
`paraphrase_augment` (diversity), `format_jitter`, `denoise_autofix`, `overlap_check`, `audit_*` scripts.
**Corpus:** `export_tools_corpus`, `export_code_corpus`, `verbalize_ontology_*`, `verbalize_obo`,
`verbalize_kg_hetionet`, `db_kg_verbalizer`, `workflow_order_verbalizer`, `concat_dedup_corpus`.
**Retriever:** `train_retriever_contrastive` (InfoNCE, family holdout), `build_retriever_eval`, `bge_probe`.
**Training/eval:** `midtrain_run`, `train_qlora_pilot`, `merge_lora`, `train_dpo_grounded`,
`eval_holdout` (logit-probe guard), `eval_holdout_vllm`, `build_multitask_sft`.
**Committee/audit:** `committee`, `audit_committee` (v1), `audit_committee_v2` (full samples, workflow-focus).
**Corpus expansion (box):** `corpus_expand/` — `common` (clean/PII/dedup/decontam), `fetch_pmc`,
`fetch_bioconductor`, `fetch_workflows` (all engines), `fetch_forums`, `fetch_vendor_docs`
(PDF→error-table→diag_fix SFT), `build_decontam`, `merge_external`, `run_all.sh`.
**GPU launch:** `gpu_bootstrap.sh`, `gpu_run_pipeline.sh` (MODEL_SIZE=small|large).

---

## 6. Documents (`docs/20260918_*` + `docs/20260912_onprem_llm/`)
- **MANUSCRIPT** — `20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md` (full write-up).
- **GPU launch** — `20260918_GPU_LAUNCH_SPEC.md` (two-model, mid-train ratio, DPO, holdout).
- **Committee audit** — `COMMITTEE_AUDIT.md` (v1 + verification), `committee_reviews/` (raw reviews).
- **This dossier** — `20260918_PROJECT_DOSSIER.md`.
- Design/plans — `MIDTRAIN_MIX`, `TASK_CATALOG`, `SFT_GENERATION_SURVEY`, `SMALL_DOMAIN_LLM_SURVEY`,
  `PERIODIC_LABS_AND_DOMAIN_TRAINING`, `TRAINING_CURRICULUM`, `RETRIEVER_EVAL`, `DATA_CONTRACT`, etc.

---

## 7. Data-quality history (audited & fixed)
| Issue | Found by | Fix |
|---|---|---|
| tools DB 90% un-mined (5.3M of ~62M) | user | `export_tools_corpus` → 16.7M deduped |
| help_text/scientific_context JSON dumped raw (97% of docs) | self-audit | verbalize both; JSON leak 10,203→231 docs |
| Galaxy-page HTML leak | self-audit | `strip_noise` (galaxy leak 83→0) |
| param type errors (nPerm=0.01 ×170) | self-audit | `schema_guard` at source + `validate_sft` cleanup → 0 |
| request truncation (~26% of queries) | committee | trim-to-sentence (1,992) / drop unrecoverable (1,900) |
| committee P0 false alarms | self-verify | caused by v1 brief slicing to [:400]; verified vs raw data |
| eval 0.0-delta | self | logit-probe guard; merged two-server eval |

---

## 8. Open items / next steps
**Laptop-doable:** paraphrase faithfulness filter; conditional/mutually-exclusive param guardrail
(schema-driven); LLM-judge label-quality sample; act on committee-v2 findings.
**Needs GPU/disk box:** corpus expansion (`run_all.sh`: PMC + Bioconductor + all-engine workflows +
forums + vendor docs); two-model training (`gpu_run_pipeline.sh`); mid-train ratio sweep; grounded DPO;
code-gen SFT from Bioconductor vignettes; base-Qwen DSL coding probe; Stage-0 re-eval of old adapter.

---

## 9. S3 layout (`s3://biomate-models-399683337364/biomate-core-local-trial/20260912/`)
```
sft/multitask_sft_enriched.jsonl          15,254 validated (canonical)
sft/multitask_sft_enriched_preclean.jsonl pre-validation provenance
midtrain_corpus/midtrain_all.jsonl        44.5M deduped
midtrain_corpus/*.jsonl                    per-shard + manifests
retriever/bge-routing-contrastive/         contrastive BGE + result
sft_27b_20260914/                          prior 27B QLoRA adapter + checkpoints
```
