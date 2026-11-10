# Multi-omic training OOM fix — paired protein/ATAC now wired into the stream

Recorded: 2026-11-09. Resolves the OOM that forced the immune-FM to train RNA-only, starving the
multi-omic fusion. End-to-end unblocked: bucket access + the two code fixes below.

## Root cause (caught live)

`immune_hybrid_llm.py --mode train` with the paired CITE/ATAC cache attached raised:
```
MemoryError: mosaic CITE/ATAC attach: appending 180349 rows to 21427922 needs ~185.1 GB > budget 111.1 GB
(5 KB/row dense; largest: expr=85.7GB, tokens=11.0GB). Lower --cap-per-study / --modality-caps
```
Two distinct bugs, both on the STREAM_CACHE (21.4M-cell) training path:

1. **The stream branch never called `attach_paired_modalities`.** It `return`ed at `immune_hybrid_llm.py`
   (~line 2867, after the DIRECTIONAL block) supporting only `MOSAIC_MODALITY_CACHES` (per-modality npz),
   so `MOSAIC_DIR/prepared.npz` (the combined 72k CITE + 108k ATAC cache) was never loaded on the stream
   path. **Fix:** call `M.attach_paired_modalities(data, cfg, work)` in the stream branch when
   `MOSAIC_DIR/prepared.npz` exists.

2. **`check_row_budget` counted the lazily-appended `expr` as a dense 85.7 GB vstack.** In
   `mosaic_modality_loader.py`, `expr` is appended via `concat_rows` (lazy `RowConcat`, never
   materialized) — only `tokens` (11 GB) is a real dense vstack. But `check_row_budget` summed ALL
   n-row ndarrays including the 85.7 GB `expr` memmap → ~185 GB > 111 GB budget → raised, dropping the
   paired cells (the "data reduced due to OOM"). **Fix:** exclude `expr` from the budget's `arrs` set
   (`... and k != "expr"`). Then need ≈ 17 GB ≪ 111 GB.

The RNA corpus itself was never the problem: 80 GB float16 memmap streams into reclaimable page cache,
~8 GB resident, model-build peak 26–34 GB, 88–113 GB available throughout.

## Result (verified)

With both fixes + `MOSAIC_DIR=mosaic_local`:
```
MOSAIC_DIR paired attach (stream): {"wired": true, "protein": {"n_paired_cells": 72317, "dim": 35,
  "source": "CITE"}, "atac": {"n_paired_cells": 108032, "dim": 512}}
EVIDENCE CHANNELS ACTIVE: modality_channels {rna:2000, protein:35, atac:512}  ← protein + ATAC now ACTIVE
model built: rss=27.4 GB peak=33.7 GB ; train_joint: train 13.5M cells / 228 studies ; mem 33/88 GB
```
The multi-omic fusion is now training on all 72,317 CITE (RNA+protein) + 108,032 ATAC paired cells,
memory-safe. (Knowledge channel dropped for this run: the mosaic attach clobbered `mod_dims["knowledge"]`
→ a dim mismatch; separate, minor, orthogonal to the fusion goal.)

## Where applied

Spark `code_20261004/`: `immune_hybrid_llm.py` (stream-branch attach call) + `mosaic_modality_loader.py`
(budget-check exclude expr). Backups: `*.bak_mosaicfix_<ts>`, `*.bak_budgetfix_<ts>`. These need
propagating into the canonical monorepo (`research/immune_llm_baseline/`) — not yet done.

## Open / next

- The knowledge-dim clobber (attach rewrites `mod_dims["knowledge"]`) should be fixed so knowledge +
  mosaic can run together.
- Heavy optional channels (proteome/methyl/imaging/bulk) still use the dense append + budget skip; same
  `expr`-exclusion fix would let them attach too (leave off for the core fusion for now).
- The decisive test — **does the trained fusion beat naive concat (0.918)?** — needs a usable checkpoint
  (hours of training). Evaluate on the GSE261278 D534 stim task once the run produces one.
