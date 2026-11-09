# Hybrid resume readiness — 29 October 2026

Prospective implementation update; **not remotely validated yet**. No numerical tests, model execution, new instance, or publication was performed for this update. The existing 50-pass remote suite predates these changes and does not cover them.

The prior runner reopened a checkpoint directory without checking full run identity and reset its process-local time allowance. `hybrid/run_guard.py` now persists an exclusive-created `run_identity.json`, checks equality on reuse, and keeps an absolute deadline across restarts (including downtime). `run_stage1.py` binds CLI settings, runtime file paths and SHA256 values (annotation, source groups, model-directory files, Python implementation), and the level configuration hash. It refuses an existing checkpoint without the new identity record. After setup, both orchestrator and generator receive only the remaining time. Hashing and level construction precede this deadline; the independent instance shutdown cap remains necessary. This is a fail-closed compatibility change: old checkpoints cannot be silently upgraded or resumed.

The application deadline is checked at existing round/batch boundaries, not a preemptive GPU interrupt. A long individual generation batch, optimizer update, verifier call or final held-out calculation can overrun it. The identity record also does not replace a single-writer scheduler/lock or cloud shutdown deadline. Do not claim hard wall-clock enforcement or concurrent-writer safety.

`hybrid/verify_restore.py` adds a separate real-model restore diagnostic. It requires externally pinned single-file base-model and checkpoint SHA256 values, loads checkpoint data only with `torch.load(weights_only=True)`, rejects empty/no-update/nonfinite states and optimizer-step disagreements, restores into a fresh CUDA ChemFM instance, then compares adapter, optimizer, metadata and CPU/CUDA RNG state exactly after serialization. It refuses non-off knowledge configuration rather than bypassing catalogue reconstruction. It never runs an update or labels the output M1-passed. A matching serialized state does not demonstrate uninterrupted/resumed trajectory equivalence.

## Prepared commands for an existing authorized EC2 GPU allocation

These commands must execute only on the authorized EC2 machine, in an isolated checkout/environment. They do not provision anything. Both mining workers were reported terminated by the mining audit agent; this note does not claim a GPU is available. Parent must confirm an existing allocation, remaining budget, single-writer output prefix and independent shutdown deadline before dispatch.

First run the focused CPU suite remotely from the `allatom_paper` directory:

```bash
CUDA_VISIBLE_DEVICES='' PYTHONPATH="$PWD:$PWD/track_e" python3.11 -m pytest -q \
  hybrid/test_run_guard.py hybrid/test_verify_restore.py \
  hybrid/test_adapters.py hybrid/test_policy_math.py hybrid/test_knowledge_parent.py \
  test_orchestrator_ia.py test_pmo_harness.py
```

Then, with `MODEL_DIR`, `ANNOTATIONS`, and a new `SMOKE_OUT` set to verified remote asset/output paths:

```bash
: "${MODEL_DIR:?}" "${ANNOTATIONS:?}" "${SMOKE_OUT:?}"
python3.11 -m hybrid.run_stage1 --mode smoke --model-dir "$MODEL_DIR" \
  --out "$SMOKE_OUT" --family F2 --seed 0 --arm hybrid --level L0 \
  --budget 100 --max-seconds 1200 --ann "$ANNOTATIONS"
```

The real-model restore diagnostic takes a particular `lora_rNNNNN.bin` referenced by the smoke's `checkpoint/ckpt.json`. Independently record the expected hashes from the approved inputs/result inventory; do not present freshly computing a hash of an unknown file as provenance verification. Set `CHECKPOINT`, `CHECKPOINT_SHA256`, `MODEL_SHA256`, and a new `RESTORE_REPORT`:

```bash
: "${MODEL_DIR:?}" "${MODEL_SHA256:?}" "${CHECKPOINT:?}" "${CHECKPOINT_SHA256:?}" "${RESTORE_REPORT:?}"
python3.11 -m hybrid.verify_restore --model-dir "$MODEL_DIR" \
  --model-sha256 "$MODEL_SHA256" --checkpoint "$CHECKPOINT" \
  --checkpoint-sha256 "$CHECKPOINT_SHA256" --out "$RESTORE_REPORT"
```

The smoke can produce zero preference updates when valid samples/pairs are insufficient. That is a meaningful diagnostic failure for learning readiness; the restore tool rejects it. Never manufacture an update or relax this condition to obtain a passing report. Do not put real mined evidence into this L0-only restore diagnostic.

## Remaining gates

- Run the new focused tests remotely; inspect failures before adding this code to a release/PR claim.
- Real ChemFM M1: sampling yield, valid preference groups, finite nonzero learning, reload, and independent resumed-update/trajectory comparison remain unmeasured. Restore equality alone is insufficient.
- Verify complete run provenance and single-writer lifecycle, and independently enforce/reconcile compute allowance. The runner currently supports the existing single `model.safetensors` layout, not arbitrary sharded-model inventories.
- Preserve the A6 copy-seed shuffled failure; complete phase stop accounting and plateau evidence; preserve the stronger A5 chronology requiring freeze before any hybrid run. See `20261029_TRACK_E_A6_REVIEW.md`. No existing proposed report is converted to frozen status here.
- Qualified immutable knowledge catalogue, review permissions, scoped mappings and split exclusions remain unavailable; no knowledge-benefit claim or final L1/L2 eligibility follows.
- F1's failed verifier floor and VOID replacement still forbid a GO conclusion. No manuscript edits were made.

Changed/new implementation files: `hybrid/run_stage1.py`, `hybrid/run_guard.py`, `hybrid/verify_restore.py`, `hybrid/test_run_guard.py`, `hybrid/test_verify_restore.py`.
