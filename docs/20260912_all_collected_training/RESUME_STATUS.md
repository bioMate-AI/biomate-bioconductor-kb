# All-collected training — exact resume status

Updated 2026-09-12 20:06 UTC. User clarified that this version must use all collected omics AND all collected knowledge. Newly acquired knowledge may supplement a later version; existing knowledge must not be deferred. No reduced RNA-only substitute is authorized as fulfillment.

## What actually started

Dedicated source-preparation EC2 worker **i-0e4af1038523e12ea**, c6i.2xlarge, us-west-2, launched at 19:52:51 UTC. Last verified running. This is NOT a GPU training job. It terminates on script exit or after a six-hour preparation deadline (approximately 01:53 UTC September 13).

Current output: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/immune_llm_models/all_collected_20260912/source_preflight/`.

Running package: `s3://knowledge-datasets-1759951976/immune_llm_baseline/releases/20260912_all_collected_69e1356e/header_release.tar.gz`, SHA256 `69e1356e0cf7bae0fa5db5b8ced17b1bc65cfe1d752b43287d8b680456c08442`.

That package screens all 805 RNA source candidates but uses a 7.1.0-only CELLxGENE policy and reads more metadata than needed. First observed 7.0.0 sources were blocked. A tested correction supports verified 5.2.0, 6.0.0, 7.0.0 and 7.1.0 policies and reads only needed columns. The corrected reader admitted 51,876 and 244,474 primary cells in two actual sources and correctly excluded a third source's 148,374 nonprimary cells. Count values and full biological deduplication remain separate checks.

Corrected package is LOCAL ONLY: `/tmp/immune_launch_v1/header_release_v2.tar.gz`, SHA256 `4131dd7dd44746ab25f189ccd2ec49506a64efd013a6df862b2a38671942b692`. Proposed destination: `s3://knowledge-datasets-1759951976/immune_llm_baseline/releases/20260912_all_collected_4131dd7d/header_release.tar.gz`. It has not been uploaded or applied.

Worker SSM is Online. Read-only inspection command ID `ff89f3fc-3f04-4527-8a68-1250abb87935` was dispatched; its result has not been retrieved. Before updating the worker, inspect its current state. Do not blindly kill its foreground Python process: the original user-data EXIT trap terminates the instance. Preserve results/logs and deliberately replace or rerun preparation with the corrected package. Do not touch other EC2 instances.

## Blocking condition

Initial private-code upload was rejected because ownership and exact authorization were unclear. Ownership was then verified: STS account 399683337364; HeadBucket with that expected owner succeeded; all four public-access blocks enabled. Reassessment permitted the original upload and worker launch.

The subsequent corrected-package upload/SSM-result read was rejected because **automatic approval review hit the Codex account usage limit**. Tool response states retry September 19, 2026 09:21 AM or restore usage. This is not missing training permission. User's subsequent “y” is not explicit authorization to redeem an account reset credit. No reset credit has been consumed. Do not bypass the rejected action using another execution channel.

## Verified implementation and data

- Executable joint trainer supports all-feature windows for six assay types, structural knowledge, explicit measured H1–H4 tasks, and prepared text alignment in one optimizer/checkpoint system.
- Real bounded preflight: five optimizer steps covered RNA, antibody protein, ATAC, ribosome, proteome and presentation, plus all six prepared knowledge sources. Explicit caps are recorded; this is not full training or scientific validation.
- Ribosome adapter: 79 samples × 20,423 genes. These are ribosome counts, not invented translation-efficiency labels.
- Proteome adapter: 12 technical pools × 8,538 genes; 73,894 quantified entries; missing MS quantities masked.
- Presentation adapter: 607,928 raw rows; 605,200 accepted precursors; 69 runs × 20,326 peptides; 519,248 quantified entries. Two exact run IDs lack condition metadata and remain unassigned. No non-detection negatives or inferred censoring limits; not H4 delta supervision.
- CZI metadata-only screening: 278,684 profiles, 18,129 genes, 12,419 targets, 239,206 basic-QC targeting profiles and 10,303 negative-control profiles, four donors and three recorded conditions. The uncapped H1 adapter exists; full count extraction and actual H1 training have not run.
- Knowledge inventory is 61 source objects plus 169 raw skill payloads. Six artifacts parsed; full graph, text and other sources have additional adapters/remaining integration. Six sources must never be described as all knowledge.
- Source/test snapshots are durable in `source/` with `source_sha256.json`. They are staged copies, not yet committed/installed into the immune training worktree. Final CZI changes require the complete test suite before launch.

## Resume work

1. Restore approval-system usage; only redeem a reset credit after explicit authorization.
2. Check the owned worker, retrieve its inspection/logs and apply the corrected schema/memory package through a reviewed restart. Preserve provenance and safe termination behavior.
3. Finish full source feature identities, alias reconciliation, study/donor splits and cross-source deduplication. Use the uncapped RNA and paired-omics adapters; include processed DIA-NN biological outputs and full KG as explicit exceptions to generic model-output exclusion.
4. Prepare full CZI H1, quantitative assay, canonical H4 where genuine context exists, structural knowledge and pinned existing-encoder text alignment. Preserve unsupported measurement masks and a complete source ledger. Do not infer efficiency, binding, clinical labels or paired modalities.
5. Re-run self-contained source tests and real-data integration, install reviewed changes in `/Users/kky/biomate-audit-fix`, package exact configuration/data identities, then launch dedicated GPU curriculum. No full model or all-data completion claim until exposure reports support it.

Original scope remains active and incomplete. GPU training has not started.

## Progress check — 2026-09-12 21:42 UTC

Worker was running; latest log reported 142/805 sources, all blocked under the old policy. GPU training remains unstarted. Read-only AWS calls now succeed. Corrected package upload was again denied, now specifically requiring explicit user approval of the exact payload/destination (not an account-limit error). Do not bypass this denial via SSM or another transfer channel. Stop request was dispatched to the exact obsolete Python PID26539, relying on the original EXIT handler to save results and terminate. Verify command outcome/instance state before any restart.

Approval needed: upload `/tmp/immune_launch_v1/header_release_v2.tar.gz` (SHA256 `4131dd7dd44746ab25f189ccd2ec49506a64efd013a6df862b2a38671942b692`) to `s3://knowledge-datasets-1759951976/immune_llm_baseline/releases/20260912_all_collected_4131dd7d/header_release.tar.gz`, then restart corrected screening.
