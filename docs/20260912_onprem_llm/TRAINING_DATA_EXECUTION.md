# BioMate training and test data preparation

Scope: main BioMate assistant, at most 32B parameters. IND/regulatory data is excluded.
Start from the working post-trained assistant checkpoint. Do not train from base for
this urgent trial: first measure the baseline and adapt only to demonstrated gaps.

## Immediate data lanes

| Lane | Source | Unit of data | Admission check |
|---|---|---|---|
| Grounded tools and parameters | Tool/workflow database | User request + retrieved candidates/schema + selected IDs/typed parameters | IDs exist, required inputs and types valid; availability independently checked |
| Corrections and repairs | Conversation/tool traces, error logs, linked commits | Complete before/failure/correction/after trajectory | Exact run linkage, rerun and artifact verifier; preserve unsuccessful attempts |
| Memory and routing | Multi-turn conversations | Prior state + correction + current request + resulting state/action | No lost IDs/units, stale facts removed, execution authorization respected |
| Results and reports | Actual workflow outputs and documents | Bounded evidence + answer with citations/numbers | Recompute numbers, validate units/source spans and distinguish QC failure from job failure |
| Teacher distillation | Approved BioMate information flows | Same runtime context/tools as local model | Teacher output is a candidate until independently verified; no hidden chain-of-thought collection |

The source inventory contains references and hashes, not approved training targets.
Knowledge records are retrieval material first. A tool description or successful
commit cannot by itself establish a correct assistant completion.

## First collection targets (targets, not collected counts)

Prepare 3,000 verified episodes in a first batch: 600 intent/extraction/memory,
900 retrieval/parameter/prerequisite, 600 tool-use/workflow-edit trajectories,
600 error diagnosis/repair, and 300 evidence-based findings/report episodes.
Sample across the client's enabled domains and weight observed failures, not just
the easiest examples. Keep long trajectories and negative examples; do not replace
missing observations with plausible text. An initial smaller batch is useful once
its provenance, verifiers and group separation pass.

Build 200 independent release cases: 40 intent/data preservation, 40 retrieval and
parameters, 40 workflow/action authorization, 40 failures and corrections, 40 results
and citations. Include unseen incident and workflow families, unavailable tools,
missing files, malformed responses, stale memory and injected instructions in
retrieved content. The existing 12 diagnostic cases are development material and
must never be advertised as a held-out release benchmark.

## Split and freeze before augmentation

Assign complete connected families (incident, conversation, study, document version,
workflow lineage and every teacher/augmentation parent) to train/dev/test. Start with
80/10/10, then review task/domain coverage; do not force percentages by separating
related rows. Exclude release test families from teacher generation, retrieval-case
mining, prompt tuning and self-improvement. Record normal production retrieval access
separately: retrieval of general tool documentation is permitted, retrieval of test
answers or test-specific traces is not. Run exact and near-duplicate checks and a
human review of ancestry before freezing the manifest. Later failure-mining goes to
development; a repeatedly tuned test set must be retired as a release holdout.

## Collection contract

For each candidate retain source locator/hash, exact application/model/prompt revision,
complete messages and tool schemas, tool-call/result IDs, context truncation markers,
dataset/workflow/run IDs, artifact hashes, verifier version/results, source-family IDs,
rights/review decision and intended task. Preserve scientific literals during redaction.
Record evidence of execution permission and any cloud/external dependency. Export only
the fields needed by reviewers and training; exclude secrets and personal identifiers.

Use `evaluation/local_trial/inventory_sources.py` to create the candidate index, then
review/link traces and pass accepted records through `prepare_episodes.py`. Its current
gate detects exact duplicates and declared connected groups; it does not detect all
semantic leakage or independently verify linked evidence. Do not auto-set accepted,
approved rights, or verifier passed merely because an LLM generated the record.

## Training and evaluation sequence

1. Freeze baseline model/runtime, trial task list, prompt hashes and evaluation cases.
2. Score direct structured outputs and real application trajectories separately;
   track unsupported execution, invented IDs/results, exact literals, tool validity,
   task success, artifact correctness, p50/p95 latency and peak memory.
3. Train an assistant-token-only LoRA/QLoRA SFT pilot on admitted examples; retain
   tool observations as context. Preserve full optimizer/scheduler/RNG checkpoints
   in S3 and prove resume equivalence before a long run. Keep total base parameters
   below 32B. Tune context length and quantization against client hardware.
4. Compare baseline and adapter on the same frozen cases. Report per-task results,
   denominators and failures. Require zero observed unauthorized executions and
   fabricated completion claims; this is a release gate, not proof of zero risk.
5. Add preference training only from verified chosen/rejected pairs sharing the
   exact same context. Re-run the full application and artifact tests after merge
   and quantization. Do not promote a model using teacher preference alone.

Teacher-provider permission and source-data rights must be established for the
intended distillation use before sending a corpus externally. Existing authorization
to use teachers does not make every dataset or provider output eligible. The current
collection scripts make no teacher API calls and no training run has started.

## Prepared inventory, 12 September 2026

The first source manifest indexes 12,312 tools, 4,198 workflow candidates and 99
repair commits. Two workflow names were excluded by the initial scope filter; all
remaining content still requires scope/rights review. Of the workflows, 690 have
a recorded `ok` status and 402 `ok_warnings`; these are candidate labels, not new
execution verification. Sixteen draft synthetic acceptance cases are prepared in
`evaluation/local_trial/acceptance_draft_v1.json`. Approved training examples and
frozen independent release cases remain zero.

The exporter now persists source-family and exact-message split assignments across
batches via `--frozen`; all 11 data-pipeline regression tests pass. Candidate-source
hashes are in `data_candidates_v1/manifest.json`. Correction/conversation log location
is still needed to construct complete verified repair episodes.
