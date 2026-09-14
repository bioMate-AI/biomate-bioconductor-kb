# On-prem model training-data sources — local, no-PII corpus (2026-09-14)

Built by `evaluation/local_trial/collect_local_corpus.py` from local sources only (no
private conversations, no dev PII). Candidate index at
`docs/20260912_onprem_llm/data_candidates_v2/` (+ `manifest.json` with per-file sha256).
Every record is `review_status=needs_review`, `eligible_for_training=False`. This is a
candidate index, not approved training data.

## Sources and volumes

| Lane / source | Count | File | Training use |
|---|---|---|---|
| Nextflow programs (.nf) | 4,920 | `nf_program_candidates.jsonl` | Nextflow understanding/generation (3,708 have `nextflow.config`; 253 README/meta; 21 schema) |
| Workflow specs — **verified_generation** | **1,092** | `workflow_spec_candidates.jsonl` | intent/spec → **verified-working** `.nf` (real_exec ok/ok_warnings + correctness pass/correct/executable) |
| Workflow specs — **nextflow_debug** | **1,056** | same | **(workflow + params + real error) → diagnosis/fix** (real_exec exec_error/fixture_failed/ran_empty_output, with `real_exec_err`) |
| Workflow specs — repair | 155 | same | workflow repair (correctness minor/major_issues) |
| Workflow specs — unverified | 1,897 | same | retrieval material only |
| Git fix commits (issue→fix) | 500 of 3,244 | `git_fix_pair_candidates.jsonl` | issue diagnosis + fix (BioMate app/logic; 0 touch `.nf`) |
| **Official Nextflow docs + patterns** | **412** | `official_nextflow_doc_candidates.jsonl` | upstream nextflow-io language reference (250 `.mdx`) + idiomatic patterns (62) |
| **All local benchmark datasets** | **885** | `all_benchmark_candidates.jsonl` | 16 more benchmarks beyond RealBio (compbiobench, lane_arbitration, model_selection, protocol_to_workflow, target_structure, prereq_recovery, …) |

> **Workflow code + documents are now content** (not just paths): each `nf_program` record
> carries the actual `.nf` `code` + `config`/`schema`/`readme` text. Official upstream
> Nextflow docs are staged under `docs/20260912_onprem_llm/official_nextflow_docs/`
> (nextflow-io docs + patterns; verify license before external redistribution). Still
> available to add: `research/bixbench_*`, `research/benchmark_evaluation/SGI-Bench`,
> `Biomni` (biomni_eval), and per-case BioMate outputs under `evaluation/results/`.
> Derived candidate JSONLs (~176 MB) are git-ignored; regenerate via
> `evaluation/local_trial/collect_local_corpus.py`.
| Docs (markdown) | 1,657 (1,333 incident/fix) | `docs_candidates.jsonl` | repair narratives + reference knowledge |
| BioMate-logic repair commits (v1) | 44 | `../data_candidates_v1/codedebug_candidates.jsonl` | BioMate param/routing/generation code fixes |
| **Public benchmarks (RealBio, gold-labeled)** | **660** | `public_benchmark_candidates.jsonl` | input→gold across 8 tasks (routing 200, param 170, protocol 100, **autofix 100 w/ error_log+expected_fix**, wf_gen 40, boin 20, pbpk 15, dd_e2e 15) |
| **Tool knowledge DB (304MB `tools`)** | **12,312** | `tool_knowledge_candidates.jsonl` | tool understanding/grounding + params (desc, help, inputs/outputs, scientific_context_v2 + verify_rate, EDAM, citations) |
| **Composition / rationale** | **9,817** | `composition_rationale_candidates.jsonl` | tool_compatibility (9,656) + workflow chains/rationale/phase reasoning |

### The 304MB knowledge DB (`galaxy_ai_tools.db`) — fully mined
55 tables. Beyond the `workflows` table (→ verified_generation/nextflow_debug/repair lanes
above), the training-usable content is: **`tools` (12,312)** rich knowledge records
(`scientific_context_v2` carries a `verify_rate` quality signal), **`tool_compatibility`
(9,656)** for composition, and **`workflow_chains`/`rationale_registry`/
`workflow_phase_rationale`** for "why" reasoning. FTS/embedding tables are indexes, not
training text. `chat_sessions`/`chat_messages` in this local copy are empty seed tables.

### Public benchmarks run through BioMate (code + input + output)
- **Code**: `evaluation/runners/` + `evaluation/runners/adapters/` (incl. the new
  `qwen27b_llamacpp.py` local adapter).
- **Inputs (gold)**: `evaluation/datasets/public_export/` (RealBio suite, 660 items) +
  `evaluation/datasets/*`.
- **Outputs (per-case BioMate answers + scores)**: `evaluation/results/` — e.g.
  `regulatory_llm_5model_v1/*.jsonl`, `comprehensive/`, `pharmacology_benchmark_v1/`,
  `multitask_crossjudge_v1/`, `lane/`, `stability/`, `admet_tdc/`, `biomni_eval1`.
  These give (input → BioMate output → gold → score) triples where present.
  The `autofix_benchmark` (error_log → expected_fix) is the cleanest gold Nextflow-debug set.

## Verification signal (key)

The workflow DB carries **real execution outcomes** (`real_exec_status`, `real_exec_err`,
`real_exec_produced`) and **correctness verdicts** (`workflow_correctness_verdict/score`).
These are used as the admission signal:
- **verified_generation** pairs are grounded in a workflow that *actually executed* — this
  satisfies the training plan's "recompute/verify before admitting" gate for generation.
- **nextflow_debug** pairs carry the *actual* failure error (e.g. `acgh`/imaging:
  `"cannot open the connection | Calls: read.table -> file"`), grounded in a real run —
  the correct source for the "debug Nextflow" capability (repo *commits* are BioMate-logic
  fixes, not `.nf` debugging, so the DB failure corpus is the right source).

## Mapping to model tasks

- **Nextflow generation** ← nf_programs + verified_generation specs (params_schema present
  on 3,058 workflows; workflow_json on 4,175).
- **Nextflow/workflow debug** ← nextflow_debug lane (1,056 real failure+error records).
- **Issue diagnosis & repair** ← git fix pairs + incident docs + workflow repair lane.
- **Routing / param-fill** ← workflow specs (descriptions on all 4,200; params_schema 3,058).
- **Knowledge / grounding** ← docs + unverified specs + nf READMEs (retrieval material).

## First-batch SFT episodes (built)

`evaluation/local_trial/build_sft_episodes.py` → `docs/20260912_onprem_llm/sft_episodes_v1/`
(derived JSONL git-ignored; `manifest.json` tracked). Assistant-token-only `{system, user,
assistant}` episodes, split by connected family, **public benchmarks held out as the test
set (0 leakage, enforced)**:

| Episode lane | Train | Dev | Source / basis |
|---|---|---|---|
| Workflow generation | 990 | 102 | verified_generation specs (real_exec ok + good verdict) |
| Issue → code fix | 385 | 41 | fix commits, **code-only** (docs commits filtered; 57 touch `.nf`) |
| Nextflow from README | 260 | 25 | repo `.nf` paired with its README |
| **release test holdout** | — | — | **660 public-benchmark items — never trained** |

Each episode carries `verification_basis`, provenance `source_groups`, `prompt_sha256`, and
`eligible_for_training=False` until human review. Leakage guard: benchmark items are emitted
only to `release_test_holdout.jsonl`.

## QLoRA SFT pilot (executed 2026-09-14)

`evaluation/local_trial/train_qlora_pilot.py` ran an assistant-token-only QLoRA SFT on the
train split. **Pipeline proven end-to-end** — loss decreased monotonically and a resume-able
checkpoint (adapter + optimizer) was saved (satisfies the plan's checkpoint/resume gate).

| step | 1 | 5 | 10 | 15 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|
| loss | 1.795 | 1.493 | 1.263 | 1.087 | 0.984 | 0.710 | 0.845 |

- **Model:** Qwen3-8B, 4-bit NF4 (QLoRA r=16), on a g6.2xlarge **spot** L4 (24 GB). Fits at
  ~11 GB. Adapter + config + trainer_state preserved to
  `s3://…/biomate-core-local-trial/20260912/sft_pilot_20260914/checkpoint-30/`.
- **Why 8B, not 27B:** the 4-bit 27B (16.8 GB) + peft's fp32 embedding upcast (+4.74 GB)
  **OOMs on 24 GB**; 27B QLoRA needs a 40 GB+ GPU (L40S/A100), which had no spot capacity.
  The pipeline is identical — the 27B run just needs the larger card.
- **Infra note:** loading the 52 GB model off the EBS root read at ~10 MB/s; moving it to the
  instance-store NVMe (`/opt/dlami/nvme`) fixed it (~260 MB/s). Put base models on NVMe.
### 27B run (on-demand L40S, 2026-09-14)

Ran the full QLoRA on **Qwen3-27B** (4-bit, LoRA r=16) on an **on-demand g6e.xlarge L40S
(48 GB)** — 200 steps over 1,635 episodes. **No OOM** (the fp32 embedding upcast that broke
on 24 GB fits at ~28 GB on 48 GB). Loss curve:

| step | 1 | 15 | 30 | 60 | 90 | 200 (final) |
|---|---|---|---|---|---|---|
| loss | 1.19 | 0.73 | 0.59 | 0.70 | 0.65 | 0.60 |
| tok-acc | 0.74 | 0.84 | 0.87 | 0.84 | 0.84 | 0.85 |

train_loss 0.589. Adapter (159 MB) + checkpoints + tokenizer preserved to
`s3://…/biomate-core-local-trial/20260912/sft_27b_20260914/`.

**Cost/spot note:** on-demand L40S = $1.86/hr. A cheaper same-hardware g6e.xlarge spot
($1.21–1.55) never had capacity during the run; the only spot that freed (g6.12xlarge, 4×L4)
was $2.75/hr — *pricier* than on-demand — so no switch was made (switching would have cost
more and restarted the run). Load the base off instance-store NVMe (`/opt/dlami/nvme`), not
EBS root (~10 MB/s vs ~260 MB/s).

- **Next (in-scope eval):** the regulatory 9-checker suite is OUT OF SCOPE (IND/regulatory
  excluded). Measure the SFT lift on the **in-scope 660-item RealBio holdout** — routing,
  param_prefill, autofix/nextflow-debug, protocol_thresholds, workflow_generation — scored
  directly against the gold labels (direct-adapter, no app stack), base-27B vs SFT-27B. Then
  human-review admitted episodes and, if warranted, preference (DPO) from verified pairs.

## Required before any training (contract)

1. Human triage of git fix pairs (keyword selection has doc-commit noise) and dedup.
2. Turn candidates into episodes: for generation, (spec/intent → verified .nf); for debug,
   (program + params + real error → diagnosis/fix). A fix pairing requires the *corrected*
   artifact where a repair example is intended.
3. Redaction pass (paths/secrets) even on local data; preserve scientific literals.
4. Freeze connected-family train/dev/test split via `evaluation/local_trial/prepare_episodes.py`
   `--frozen` before augmentation. Exclude release-test families from teacher/mining.
5. Only then: LoRA/QLoRA SFT on admitted examples; re-benchmark; DPO from verified pairs.

## Deferred / gated

- **Dev conversation corpus** (chat_sessions: 2,077 convos / 6,463 msgs, with
  workflow_id/invocation_id links → verifiable; correction_log empty; audit_logs 1.2M).
  Scoped read-only via SSM. Bulk export gated: it is production PII, and the dev instance
  role (`BioMateEc2DeployRole`) is denied S3 write, so any export needs a redact-in-place
  path + rights sign-off. Not exported.
