# ChIP-seq sample data — provenance

## `CTCF_SE_ChIP_chr22_50k.bed.gz` / `CTCF_SE_CTRL_chr22_50k.bed.gz`

- **What:** Real public single-end CTCF ChIP-seq (treatment) + matched input
  control tracks, chr22 subset (~50k reads each). BED format, gzip-compressed.
- **Source:** [macs3-project/MACS](https://github.com/macs3-project/MACS) test
  fixtures (`test/CTCF_SE_ChIP_chr22_50k.bed.gz`,
  `test/CTCF_SE_CTRL_chr22_50k.bed.gz`), vendored byte-identical so the
  BioMate ChIP-seq peak-calling demo does not depend on a live GitHub raw
  download at Nextflow launch time (Batch head nodes often cannot reach
  `raw.githubusercontent.com`).
- **License:** MACS/MACS3 is BSD-licensed; its bundled test tracks are intended
  for redistribution with the project. Not synthetic; not fabricated.

## Usage

Default demo inputs for
`genomics/perform_chipseq_peak_calling_with_macs2` when
`--chip_seq_file` / `--control_file` are unset.
