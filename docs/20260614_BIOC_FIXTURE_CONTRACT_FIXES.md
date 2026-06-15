# Bioconductor fixture-contract fixes (Class A + Class B)

Date: 2026-06-14
Branch: `fix/bioc-fixture-contract` (off `bioc/v2-qc-audit-panel`)
Scope: fix the INPUT DATASETS (fixtures) + the input-staging harness — NOT the production
`.nf` workflow analysis logic.

## Root cause (general)

Each bioc subworkflow declares its inputs in a `// Input:` comment using a *logical base
token* (e.g. `sce2`, `fit2`, `nmr`). The local/fleet validation harness runs the matching
`*.fixture.R` in the workflow's container, then stages each declared input **by that bare
token** (`run_dir/<token>`, basename preserved). But the workflow R body very often reads a
*literal filename with an extension* — `readRDS("sce2.rds")`, `file.exists("fit2.rds")`,
`loadDb("txdb.sqlite")`. The bare-token staged file therefore can't be found, OR a synthetic
placeholder gets staged and read as "unknown input format" / "cannot open the connection".

Two failure classes followed from this single contract gap:

* **Class B — filename mismatch:** fixture emitted the wrong name (or nothing), so the exact
  `// Input:` filename the workflow reads was never on disk.
* **Class A — wrong binary/rds format:** fixture wrote a non-matching or non-portable
  serialization (missing `.sqlite` TxDb, HDF5Array pointing at an un-staged backing `.h5`,
  object missing entirely) → `readRDS`/`loadDb` failed.

## General fixes applied

1. **Harness (input staging), `nextflow_executor._build_bioc_entry_wrapper`:** new helper
   `_resolve_read_filename(nf_text, base)` inspects the workflow body and stages each declared
   input under the *literal filename the workflow actually reads* (preferring `.rds`, falling
   back to the first referenced extension, keeping the bare token when the workflow reads it
   bare, preserving directory `/` tokens). This satisfies the input contract generally without
   editing any `.nf`. Unit-tested against 8 representative workflows; all resolve correctly.

2. **Fixtures, dual-emit footer (`# [biomate-fx-dual]`):** for every `.rds`-object input, emit
   the real serialized object under BOTH `<token>` and `<token>.rds` so any staging harness
   (bare-token or extension-aware) collects a real object, never a synthetic placeholder.

## Per-fixture fixes (Class A — expected class → serializer)

| Workflow | Object / file | R class | Serializer |
|---|---|---|---|
| nanomethviz/downstream_export… | nmr | NanoMethResult (S4) | saveRDS + dual |
| wpm/eset_msnset_to_plate_map | my_MSnSet_object | MSnSet | saveRDS + dual |
| plgem/main | expression_set | ExpressionSet | saveRDS + dual |
| gg4way/* | dds / efit / rfit+contr.matrix | DESeqDataSet / MArrayLM / DGELRT+matrix | saveRDS + dual |
| mumosa/main | sce2 | SingleCellExperiment | saveRDS + dual |
| spotlight/main | sce, spe | SingleCellExperiment, SpatialExperiment | saveRDS + dual |
| metagenomeseq/longitudinal | mouseData | MRexperiment | saveRDS + dual |
| geneplotter/single_chromosome | sample.ExpressionSet, chrObj | ExpressionSet, list | saveRDS + dual |
| scry/large_data_deviance | h5counts, sce | DelayedArray (in-mem), SCE | saveRDS (realized, self-contained) + dual |
| clusterstab/main | fibroEset | ExpressionSet | saveRDS + dual |
| aggregatebiovar/main | small_airway | SingleCellExperiment | saveRDS + dual |
| diggit/main | gbmExprs/CNV/TFregulon/Mindy/CNVnormal | matrix / regulon / data.frame | saveRDS + dual |
| methimpute/enrichment_analysis | model | methimputeBinomialHMM | saveRDS + dual |
| raer/novel_editing_detection | txdb.sqlite + 2× .gr + fasta + bam | TxDb (saveDb), GRanges (saveRDS) | saveDb + saveRDS + indexFa/indexBam |

`scry`: the original fixture saved an `HDF5Array` whose `.rds` only stores a pointer to an
external `.h5` the harness never staged → switched to an in-memory `DelayedArray` so the `.rds`
is self-contained while still exercising scry's DelayedArray code path.

`raer/novel_editing_detection`: previously emitted only `bams.bam` + `fasta.fasta`; now emits a
REAL `loadDb`-compatible TxDb (`saveDb` → `txdb.sqlite`), both GRanges (`chr4snps.gr`,
`rmsk_hg38.gr` via `saveRDS`), an indexed FASTA and indexed BAM, all consistent with the BAM's
reference sequence.

## Per-fixture fixes (Class B — filename / missing input)

| Workflow | Fix |
|---|---|
| affycoretools/interactive_venn | dual-emit fit2/contrast/design (.rds already written) |
| cnordt/main | dual-emit CNOlistPB/modelPB |
| plgem/step_by_step_mode | dual-emit ExpressionSet |
| classifyr/multi_view_integration | dual-emit measurementsDF/classes |
| spotlight/two_step_deconvolution | dual-emit sce/spe |
| degcre/main | dual-emit subDegGR/subCreGR |
| spia/spia_with_custom_kegg_data | **was** `saveRDS(..,"DE_Colorectal")` (no ext) → now `DE_Colorectal.rds` / `ALL_Colorectal.rds` |
| ropls/multi_assay_experiment | **was** `saveRDS(mae,"input.rds")` → now `nci_mae.rds` (the name the wf reads) |
| rmagpie/main | added missing `vV_newSamples.txt` (copy from Rmagpie extdata, else synth from ExpressionSet) |
| camutqc/main | added missing `Pan-cancer-hg38.rds`; switched VCF source to CaMutQC's OWN extdata (VEP-annotated, has CSQ header vcfToMAF needs) instead of generic VariantAnnotation VCF |
| switchbox/main | **created** fixture: `data(matchedDatasets)` → matTraining/trainingGroup/matTesting (.rds + bare) |
| fgga/main | **created** fixture: `data(CfData)` → dxCf/tableCfGO/nodesGO (.rds + bare) |

## Known limits (honest)

* `// Input:` declarations that are *prose* rather than filenames (`plgem/main`,
  `plgem/step_by_step_mode`, `ropls/*` say "ExpressionSet object" / "SummarizedExperiment
  object") cannot be staged by the test harness, which tokenizes that prose. The *production*
  executor wrapper now stages correctly only when the token matches the read name; for these
  prose declarations the harness-side staging still needs the `// Input:` line corrected to the
  literal filename (an `.nf` edit deliberately NOT made here per the "fixtures only" directive).
  The fixtures themselves emit the correct file.
* `tximeta/linked_transcriptomes`: fixture already emits all three declared inputs correctly;
  its failure is in workflow logic (`writeLines` into a created index dir failing to open a
  connection), which is `.nf` analysis logic and out of scope.
* `aspli/main`: fixture is correct (real BAM dirs + GTF); the "directory not found" was a
  harness directory-staging issue, addressed by the executor staging fix (trailing-slash
  tokens preserved).

## Verification

* All 28 changed/new `.fixture.R` files pass `Rscript parse()` (2 syntax errors found & fixed:
  camutqc `stopifnot` dynamic name, raer top-level `if/else` line split).
* Dual-emit + `.emit` + rename logic verified by base-R roundtrip: both `<token>` and
  `<token>.rds` produced, `readRDS` loads the correct class under either name.
* `_resolve_read_filename` unit-tested against 8 real workflows (Class A + B + directory +
  already-extensioned) — all resolve to the expected staged filename.
* `nextflow_executor.py` byte-compiles (`py_compile` OK); full import blocked only by a missing
  unrelated third-party dep (`a2wsgi`) in this sandbox.
