# Staged full-scale wiring changes

Source is staged only, copied from training worktree. `implementation.patch` is the exact diff. Apply intentionally; no production or remote execution performed.

## Activation

Set cfg `bottleneck_mode="knowledge2_joint"`, `label_policy="observed_only"`, and a real `proto_init` membership matrix. Use cfg `required_objectives` to list objectives that each particular source batch is obliged to supervise. Keep weights explicit. This supports heterogeneous source batches: absent non-required tasks are skipped, never assigned zero labels. Inspect returned loss-parts keys and count observed labels in the parent scheduler.

The new mode adds joint_projection and joint_norm and combines the knowledge latent with projected backbone/omic fusion before heads. Legacy knowledge2's state keys and behavior remain unchanged. This is a distinct model configuration requiring its own run/checkpoint identity, not silent legacy checkpoint migration. Unknown/provenance constraints remain the parent's responsibility.

Observed-only loss requires explicit Boolean, exact-shape masks for supplied labels, selects observed entries before computing losses (masked NaNs safe), rejects nonfinite observed values, checks binary bounds and required task support. Label names: y (annot/lin/target), programs (biomk), responder (strat), durability, inflam, immunogenic (recognition), presented (presentation). Contrast uses observed y entries. Study adversary assumes a valid observed study index for every row. Genetics/pathway regularizers require genuine configured support. Required unsupported objectives fail.

slice_batch now transports optional labels, masks and peptide features, and does not require placeholder programs/responder/y where absent. Internal training forward calls transport pep to peptide heads. build_mods's all-present masks use expr device/dtype.

## Verification

`/opt/homebrew/bin/python3 -m unittest -v test_fullscale_wiring` passed 5 tests on 2026-09-12. Synthetic wiring tests show nonzero gradients in backbone, omic fusion, learned pathway/de-novo, joint projection, peptide encoder, all advertised task heads, contrastive and study heads; all required loss terms are present. These are implementation tests, not biological validation or proof that real datasets support every task.

## Limits

- Corpus streaming, source/task scheduling and real observed labels are not added here.
- CLI lists the new mode, but observed-only policy and per-batch objective contract are a configuration API, not a completed full-scale CLI workflow.
- Legacy joint_loss remains for legacy reproduction; a full-scale driver must explicitly select observed_only.
- Generic legacy train_joint evaluation still expects annotation labels; heterogeneous task-only batches require the parent's scheduler/evaluator.
- Target CE remains annotation proxy, not perturbation effect; durability/inflammation labels must not be repurposed as arbitrary proxies.
- Peptide prediction is a separate branch; no unsupported claim of peptide-context coupling.
- Masked label values are safe, but missing/nonfinite input features require upstream valid observation handling; legacy omic masks are whole-modality rather than feature-level.
- No changes to clinical patient aggregation or leakage control were made.

## Follow-up fixes and checkpoint module

Independent review identified int32 y transport regression and absent-modality NaN propagation. y casting to int64 is restored. Whole-modality masks are now explicit binary [batch,1]; absent rows are sanitized BEFORE gate/encoder evaluation. Nonfinite observed inputs fail. Regression tests prove unchanged predictions and zero missing-input gradients. This does not add feature-level masks.

`resumable_checkpoint.py` adds local atomic fsync/replace persistence of model, optimizer, scheduler, scaler, Python/NumPy/Torch/CUDA RNG, epoch, next batch and caller-provided sampler state. Source-manifest/schema/config SHA256 identities, component presence and CUDA topology are checked before state restoration. Only trusted local torch-pickle checkpoints may be loaded. Save at an optimizer-step boundary; no in-flight accumulated gradients or worker-prefetch queues are recorded. Deterministic indexed sampling and deterministic kernels are caller responsibilities.

Combined verification now passes 11 tests: 7 wiring + 4 checkpoint. Exact CPU dropout+AdamW resumed trajectory and optimizer tensors match over five continuation steps. CPU GradScaler state roundtrip is tested. CUDA RNG capture is implemented, but GPU trajectory is not tested on this machine.
