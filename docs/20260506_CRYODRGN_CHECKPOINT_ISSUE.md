# cryoDRGN + BioEmu: Spot Interruption / Checkpoint Gap

**Date:** 2026-05-06  
**Status:** Known issue — deferred to next phase  
**Priority:** P1 (blocks reliable long GPU runs on spot instances)

---

## Problem

Both cryoDRGN and BioEmu workflows lose all progress when the underlying Batch job is interrupted (spot reclaim, time limit, OOM kill). Root cause: intermediate results are written only to the container's local filesystem and uploaded to S3 only when the Nextflow task exits successfully.

### cryoDRGN (CRYODRGN_TRAIN)
- Writes per-epoch checkpoints to `cryodrgn_output/weights.N.pkl`, `z.N.pkl` locally
- Supports `--load weights.N.pkl` flag to resume from a checkpoint
- **Gap:** no S3 sync between epochs; spot interrupt loses all N completed epochs

### BioEmu (BIOEMU_SAMPLE)
- Generates conformers sequentially, writes `ensemble_pdbs/conf_NNNN.pdb` as it goes
- **No native resume/checkpoint API** — BioEmu's `sample.main()` must run to completion
- **Gap:** all generated conformers lost on interrupt

---

## Fix Plan (next phase)

### cryoDRGN — add per-epoch S3 checkpoint sync
In `cryo_heterogeneity/main.nf`, wrap the `cryodrgn abinit` call with a background sync loop:

```bash
# After starting cryodrgn abinit (in background):
cryodrgn abinit ... -o cryodrgn_output/ &
CRYO_PID=$!

CKPT_S3="s3://biomate-nextflow-work/pilot/ckpt/cryodrgn-${task.index}/"
while kill -0 $CRYO_PID 2>/dev/null; do
    sleep 300  # sync every 5 min
    aws s3 sync cryodrgn_output/ $CKPT_S3 --exclude "*.log" --quiet
done
wait $CRYO_PID
```

On retry, detect checkpoint and add `--load` flag:
```bash
LATEST_CKPT=$(aws s3 ls ${CKPT_S3} | grep "weights\." | sort | tail -1 | awk '{print $4}')
if [[ -n "$LATEST_CKPT" ]]; then
    aws s3 cp ${CKPT_S3}${LATEST_CKPT} cryodrgn_output/${LATEST_CKPT}
    RESUME_FLAG="--load cryodrgn_output/${LATEST_CKPT}"
fi
cryodrgn abinit ... $RESUME_FLAG
```

### BioEmu — add per-conformer S3 checkpoint
In `protein_dynamics/main.nf`, modify the BioEmu Python block to:
1. Check S3 for existing partial conformers before starting
2. Write each conformer to `ensemble_pdbs/` immediately after generation
3. Sync `ensemble_pdbs/` to S3 every 10 conformers

```python
# At start: restore partial progress
existing = boto3.client('s3').list_objects_v2(Bucket='biomate-nextflow-work',
    Prefix=f'pilot/ckpt/bioemu-{prefix}/')
n_done = len(existing.get('Contents', []))
print(f"[RESUME] {n_done} conformers already in S3, starting from {n_done}")

# Modify bioemu_main to stream-write via callback:
for i, conformer in enumerate(stream_sample(sequence, ...)):
    save_pdb(conformer, f"ensemble_pdbs/conf_{n_done+i:04d}.pdb")
    if i % 10 == 0:
        subprocess.run(['aws', 's3', 'sync', 'ensemble_pdbs/', ckpt_s3])
```

---

## Workarounds Applied (current phase)

| Issue | Workaround |
|-------|-----------|
| Spot reclaim kills cryoDRGN | Moved CRYODRGN_TRAIN to on-demand `galaxy-cloud-queue-gpu` |
| 8h time limit kills TRPV1 BioEmu | Extended to 24h; reduced n_samples 200→100 |
| OOM on T4 with batch_size=256 | batch-size-sgd 256→128 (7 GiB fits in 14.56 GiB T4) |
| CPU-only torch in cryo-heterogeneity-nf | v1.0.2: explicit `torch==2.1.0+cu121` via cu121 index |
| DataLoader crash (shared memory) | `--num-workers 0` |
| MKL threading conflict | `MKL_THREADING_LAYER=GNU` |

---

## Files to modify in next phase
- `backend/nf-core-workflows/modules/biomate-ai-tools/cryo_heterogeneity/main.nf`
- `backend/nf-core-workflows/modules/biomate-ai-tools/protein_dynamics/main.nf`
- Add: `backend/lib/nextflow_utils/s3_checkpoint.sh` (shared helper)
