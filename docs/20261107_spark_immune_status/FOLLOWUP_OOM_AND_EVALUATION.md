# Follow-up: OOM, S3 and evaluation repairs

Recorded 2026-11-07 CST.

## OOM evidence

Kernel records confirm global host OOM kills on November 5 affecting Python and system services. These records do not identify the responsible project. Do not attribute them to immune training without command/process provenance. Immune logs inspected here show CUDA busy/unavailable and operation-not-permitted errors, which are distinct from allocation OOM. Raw excerpts are retained in immune_oom_excerpt.txt.

The GPU smoke test only validates execution, not workload capacity. Before a real rerun: use one job, bounded data loading and worker counts, explicit memory budget, small batches, and host plus accelerator memory monitoring. Avoid full-corpus copies: 22 million x 2,000 float32 values alone require approximately 176 GB, exceeding host capacity before model or optimizer allocations. The existing float16 memmap must remain streamed. A container memory limit alone is not proof that all GPU/unified allocations are accounted for.

## S3 reconciliation

Listed 2,123 objects in the immune_llm_models prefix. This is a scoped inventory, not a search of every bucket or unrelated project. Recent retrieved results are retained in s3_recent_results.json.

October 29 B2 pooled few-shot evaluation: 47,612 test cells, 107 studies, five draws. At k=4 the two encoder seeds score 0.5309/0.5311 versus raw 0.3021 and PCA 0.3506. At k=256 raw 0.6230 exceeds embeddings 0.5816/0.5895. This supports a low-label-budget benefit under the pooled protocol, not universal superiority or within-study validation.

Geneformer V1-10M frozen probe reports 0.5076; scVI seed 0 reports 0.5744. These belong to the capped B2 benchmark, not the 22-million-row fs_long evaluation. Do not compare those absolute scores across splits.

October 28 provenance confirms RNA, knowledge, TCR, protein, ATAC and genetics channels. PINNACLE KG inactive. These records do not establish integration of all available omics or skills.

## Code and tests

Applied repairs to /Users/kky/biomate-audit-fix/research/immune_llm_baseline:
- eval_protocols.py: labelled-training-only standardization; required trainable parameter checks; explicit adaptation/query split; per-study classifiers and skipped-study accounting.
- finetune_pretrained_vs_scratch.py: removed whole-dataset scaling; strict trainable-weight presence; device-aware batches and finite-loss checks.
- calibrated_metrics.py: average rank for exact ties; reject singleton/nonfinite retrieval inputs.
- fewshot_baselines_capped.py: preserve pooled historical result and add separate within_study_v2 output.
- test_eval_protocols.py: six behavior regression tests.

All six tests passed on Spark in NGC 25.04, CPU-only container limited to 4 GiB and two CPUs (1.359 seconds). Local test run passed five tests but the sklearn-dependent case failed on an existing SciPy import incompatibility; remote test resolves validation of the helper behavior, not the local environment defect. Python syntax compilation passed locally. Full model/data integration and memory profile are still pending. No new training or biological performance claim follows from synthetic tests.

Copies of repair sources are retained in eval_repair/. Existing historical results and checkpoints were preserved.
