# Dataset panel — formats, safe editing, folders (2026-11-11)

## Why
The founder asked how many workflow data formats the dataset panel handles, whether it was fully
tested, whether Galaxy already had this code, how folders are handled, and whether files can be
edited. Reading the code and measuring on dev showed: six formats profiled, header-less tables read
wrongly, binary files reported as broken, folders treated as plain containers, and an in-place
editor that could corrupt CSVs.

## Baseline (dev eeb1219c, `e2e/dataset-format-matrix.e2e.ts`, Galaxy's own fixtures)
3 PASS / 13 PARTIAL / 14 FAIL across 30 formats + 2 folders (details:
`docs/20261111_DATASET_FORMAT_MATRIX.md`).

## What changed
| PR / branch | Change |
|---|---|
| #384 | JSONL nested tables shown as structure (record view, json-edit-react tree), nested-table QC incl. extraction row cap (EPAR: 69% of 2,281 tables cut at 7 rows) |
| #385 | In-place edits rewrite only the edited cells (`server/delimited-text.ts`, Python-csv-compatible, cross-checked cell-by-cell); edits carry the shown value → 409 on mismatch; non-UTF-8 refused; editing on the full rows table; version Compare uses the same parser |
| #386 (`feat/ds-formats`) | Profiler reuses Galaxy `galaxy.datatypes` (`galaxy_formats.py`): identification + `set_meta` metadata; FASTA/MTX/h5ad/loom/BAM/CRAM/GTF/GFF3/BED/SDF/PDB/xlsx profiles; header inference shared by profiler, rows reader and editor; binary-before-text; findings use the user's filename; leakage (leave-one-out) and imbalance (class ratio) fixes |
| #386 (`feat/ds-preview`) | gz/bgzip text preview, narrowPeak/broadPeak/bedGraph/BEDPE, BED12, TIFF state, format chip, FASTQ viewer fix, file viewer beats sample table (PDB), spheres when no backbone (Si.cif) |
| #386 (`feat/ds-rename`) | Rename/move files, rename folders (all-or-nothing, 409 on collision), collision-free object keys |
| `fix/ds-polish` | Multi-line cells edit in a textarea (an `<input>` dropped line breaks), ↵ display, count-safe English QC wording, rows/columns cards only for tables, e2e harness fixes, EPAR extractor keeps all rows |
| `feat/ds-folders` | Folder profile: Galaxy `auto_pairing` (fallback port tested against the Galaxy source), orphans, samplesheet download, 10x recognition (cells × genes from a 64 KB ranged read), per-file FASTQ/10x findings use the folder context |

## Verified on dev 63ecd58f
- `e2e/dataset-edit-safety.e2e.ts` PASS (bytes exact; stale edit → 409).
- `e2e/project-file-rename.e2e.ts` PASS.
- Format matrix re-run: ~22 PASS, rest PARTIAL, 0 FAIL (binary formats show QC metadata but no
  in-browser preview; folders not yet recognised — fixed by `feat/ds-folders`, pending deploy).
- Container probe: all 309 Galaxy fixtures profile in 3.5 s total (max 213 ms).

## Process notes
- A deploy-wait loop matched its own process with `pgrep -f "bash .*sync_to_dev\.sh"` and waited on
  itself 30 min; anchor `^bash scripts/sync_to_dev\.sh`.
- Dev's root disk hit 100% (frontend build "no space left on device"; the lease release failed too).
  Routine prune freed 6.7 GB; ~40 GB of old tagged images await the owner's decision.
- Local Python 3.9 cannot import `galaxy.ai` (Anaconda SciPy crashes); the gate's module-load check
  runs in dev's Galaxy container instead (`remote_import_check.sh`).
- EMA answers 429 for EPAR URLs that do not exist (not only when throttling): bounded retries.

## Open
- Binary formats (BAM, h5ad, xlsx, …): QC metadata only, no in-browser preview.
- Samplesheet: no strandedness column; lanes not merged; no "save to project".
- Folder view opens on every folder-row click (also when collapsing).
- EPAR re-extraction with all rows: running on Spark.
