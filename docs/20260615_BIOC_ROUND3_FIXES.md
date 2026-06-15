# Bioconductor Round-3 Real-Execution Fixes (2026-06-15)

Branch: `fix/bioc-round3` (off `integration/next-phase`).
Validation harness: `backend/scripts/realrun_test_bioc_workflows.py` (per-image rlib
cache via `rlib_for(img)`), `--workers 1`, ECR registry
`399683337364.dkr.ecr.us-west-2.amazonaws.com/`. Each workflow runs its REAL R
script through Nextflow (no `-stub`) in its dependency-complete container, on a
synthesized realistic input, asserting declared outputs are produced and
non-trivial.

Six workflows that still failed after two prior rounds were diagnosed to the real
R/exec error (read from `/tmp/*_result.json` `err` + per-process `.command.err`),
fixed at the correct layer, and re-run until green.

## Results

| # | Workflow | Real root cause | Fix (layer) | Re-run |
|---|----------|-----------------|-------------|--------|
| 1 | `wpm/expressionset_to_plate_map` | Fixture built an MSnSet whose pData had `Type`/`Treatment` columns, but the workflow calls `convertESet(obj,"Environment")` + `pData$Environment` → grouping column missing; MSnbase also absent from the wpm biocontainer. | Fixture: build a plain **ExpressionSet** (Biobase, in-container) with a real `Environment` grouping factor (per the wpm vignette). No MSnbase needed; `convertESet` reads only `Biobase::pData`. | **ok_warnings** (3/3 outputs) |
| 2 | `tximeta/mixed_reference_oarfish_import` | (a) Fixture wrote no `<name>.meta_info.json` sidecar — `importData(type="oarfish")` requires it with both `annotated_transcripts_digest` and `novel_transcripts_digest`. (b) Workflow called bare `updateMetadata(se)` / `updateMetadata(se, txpData=…)` on indices with **no registered metadata** → tximeta bug `object 'rowdata' not found`. | Fixture: synthesize the oarfish `.meta_info.json` with both required digests (added to `// Input:`), plus consistent quant/coldata/novel_gr. Workflow (.nf R logic): `setTximetaBFC` to temp; **`makeLinkedTxpData()`** to register the novel digest→GRanges (the documented mixed-ref step); restrict `updateMetadata(order=…)` to resolvable indices. | **ok** (rc 0, 8 outputs) |
| 3 | `methimpute/main` | `main.fixture.R` was a raw FASTA string placeholder — produced neither declared input (`arabidopsis_bsseeker.txt.gz`, `arabidopsis_sequence.fa.gz`). | Fixture: synthesize a gzipped FASTA, then derive a real 8-column BSSeeker report (`importBSSeeker` format: chr, C/G nucleotide, position, context, …, methylated, total) whose positions are GENUINE cytosines extracted from that FASTA via `methimpute::extractCytosinesFromFASTA` → consistent with `inflateMethylome`. | **ok** (rc 0, 8 outputs) |
| 4 | `geneplotter/single_chromosome_expression_plotting` | Fixture's `buildChromLocation("hgu95av2")` overflows R's fixed ~8 MB C protection stack (and node-stack on serialize). Prior round flagged this as an unfixable sandbox ENV limit (`ulimit -s` can't be raised in-container — confirmed: soft limit stays 8192). | Fixture: build an **equivalent lightweight `chromLocation` S4 object directly** from the genuine `hgu95av2CHRLOC`/`hgu95av2SYMBOL` maps for only the probes in use (alongChrom reads only the `chromLocs` list + `geneSymbols` env slots). Avoids the full-annotation AnnDbBimap recursion entirely — real annotation data, no demo data. | **ok** (rc 0) |
| 5 | `tximeta/linked_transcriptomes` | Workflow created scratch dirs with RELATIVE names (`quant_output`, `custom_index`) inside the staged work dir → intermittent `cannot create file 'quant_output/quant.sf', reason 'Not a directory'` (collision with the staged-input layout). Standalone it passed; under the harness's staging it failed. | Workflow (.nf R logic): root all scratch dirs under an absolute `tempdir()`-based path with explicit `dir.create`/`file.copy` success checks. | **ok** (rc 0, 6 outputs) |
| 6 | `camutqc/multi_caller_integration` | Fixture copied an unrelated `VariantAnnotation` example VCF via `system.file` (demo data, not VEP-annotated) → `vcfToMAF` couldn't parse it; PoN file had wrong columns. | Fixture: synthesize 3 genuine **VEP-annotated paired-tumor/normal somatic VCFs** (MuSE/VarScan2/Mutect2) — proper `##tumor_sample/normal_sample`, GRCh38, `CSQ` Format header (`Allele\|Consequence\|IMPACT\|SYMBOL\|Gene\|…`), real Ensembl IDs/HGNC symbols, exonic missense calls with high tumor depth+VAF so they pass CaMutQC's default filters; PoN as `CHROM POS REF ALT` table. Also fixed `packageVersion("camutqc")`→`"CaMutQC"`. | **ok** (rc 0, 4 outputs; union of 6 variants) |

## Verified green: 6 / 6

All six reach `ok` or `ok_warnings` (declared outputs produced, non-trivial,
input-derived) on a real `nextflow run` in the dependency-complete container.
`ok_warnings` = a trailing non-fatal warning sets a non-zero exit AFTER the real
outputs are written (the harness treats produced+non-trivial outputs as success).

## Notes / discipline

- No demo data introduced: every fixture synthesizes real user-style inputs (oarfish
  quant+meta_info, BSSeeker report derived from FASTA cytosines, VEP somatic VCFs,
  ExpressionSet/chromLocation from genuine annotation maps). The previous geneplotter
  fixture and camutqc fixture that used `system.file`/`buildChromLocation` demo paths
  were replaced.
- No params stuffed into production `.nf` to dodge errors. The two `.nf` R-logic
  changes (oarfish `makeLinkedTxpData`+`order`, linked_transcriptomes absolute scratch
  dirs) are genuine analysis/robustness fixes; the camutqc `.nf` change is a real
  `packageVersion` package-name typo fix.
- `// Input:` was extended ONLY for `mixed_reference_oarfish_import` to declare the
  mandatory oarfish `meta_info.json` sidecar — a real required co-input, not a cheat.
- The geneplotter C-stack overflow that prior rounds documented as an unfixable ENV
  limit IS fixable: the proper fix is to not call `buildChromLocation` on the full
  annotation at all, but assemble the small equivalent `chromLocation` the plot
  actually reads.
