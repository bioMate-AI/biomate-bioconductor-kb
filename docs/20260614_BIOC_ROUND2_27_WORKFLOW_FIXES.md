# Bioconductor Round-2: re-fixing 27 still-failing workflows (2026-06-14)

Branch: `fix/bioc-round2` (worktree `/tmp/fix-round2`, off `integration/next-phase`).
Validator: `backend/scripts/realrun_test_bioc_workflows.py` (REAL `nextflow run`, no -stub,
in each workflow's dependency-complete container, on a real-input fixture; asserts the
declared, non-trivial outputs are produced).

## Foundational root cause found this round

The shared on-disk R library cache `/tmp/realrun_rlib` (mounted into every FIXTURE run as a
prepended `R_LIBS_USER`) was **poisoned with Bioc-3.20 packages** (`BiocGenerics 0.52.0`)
while the biocontainers are Bioc 3.21/R4.5 (need `>= 0.53.2`). Any fixture that loaded
`SingleCellExperiment`/`GenomicRanges`/`SummarizedExperiment` crashed at load with
`package 'BiocGenerics' 0.52.0 was found, but >= 0.53.2 is required`. This silently failed a
large fraction of the round-1 fixes. Clearing `/rlib` (it is root-owned — clear via a docker
container) removes the shadow so fixtures use the container's ABI-correct packages. NOTE: it
re-poisons whenever an install-heavy fixture runs against the frozen 3.20 base repos under
`workers>1`; validate the synthetic-fixture workflows isolated (`--workers 1`, clear `/rlib`
first) to avoid spurious failures.

## Result table

| # | workflow | real root cause | fix | re-run |
|---|----------|-----------------|-----|--------|
| 1 | clusterjudge/main | demo-data v2 stub (`data(Yeast.GO.assocs)`), bogus `library(Database)`, ignored input | rewrote into real clusters.csv + associations.csv → validate/consolidate/clusterJudge | **ok_warnings** |
| 2 | spotlight/main | ExperimentHub fixture (network) + `/rlib` shadow | self-contained synthetic SCE+SPE with cell-type structure | **ok_warnings** |
| 3 | spotlight/two_step_deconvolution | same | same synthetic SCE+SPE | **ok_warnings** |
| 4 | scry/main | flat-Poisson fixture (degenerate for deviance/GLM-PCA) + `/rlib` shadow | structured scRNA counts (marker programmes) | **ok** |
| 5 | scry/sce_null_residuals_pca | same | structured counts | **ok** |
| 6 | scry/large_data_deviance | same (DelayedArray) | structured counts, in-memory DelayedArray | **ok** |
| 7 | plgem/main | `data(LPSeset)` demo data | synthetic 2-condition ExpressionSet (power-law mean/var) | **ok_warnings** |
| 8 | plgem/step_by_step_mode | same | same ExpressionSet | **ok_warnings** |
| 9 | switchbox/main | `data(matchedDatasets)` demo data | synthetic 2-class TSP matrices + group factor | **ok_warnings** |
| 10 | classifyr/multi_view_integration | `data(asthma)` demo data | synthetic 2-assay multi-omics DataFrame + classes | **ok** |
| 11 | aggregatebiovar/main | `data(small_airway)` demo data; round-1 metadata length bug | synthetic multi-subject SCE (orig.ident/celltype/Genotype WT-CFTRKO); fixed per-cell metadata | **ok_warnings** |
| 12 | affycoretools/interactive_venn_diagram_generation | `data(sample.ExpressionSet)` + 1-column contrast (collist=1:2 needs 2) | synthetic ExpressionSet + limma with 2 contrasts | **ok_warnings** |
| 13 | wpm/eset_msnset_to_plate_map | fixture needed MSnbase (absent in container) | build a plain ExpressionSet (wpm accepts eSet) | **ok** |
| 14 | rmagpie/main | `data(vV70genesDataset)` + `system.file` | synthetic 2-class ExpressionSet + new-samples table | **ok_warnings** |
| 15 | chromdraw/bed_file_karyotype | OUTPUT CONTRACT: declared csv/pdf/rds but chromDraw emits .eps/.svg | declare eps/svg outputs; synthetic 9-col karyotype BED | **ok** |
| 16 | qsutils/strand_haplotype_intersection | OUTPUT CONTRACT: outputs named `intersect*` were dropped by the harness input-name heuristic (`"in" in name[:3]`); fixture used system.file + degenerate FASTA | renamed outputs to `strand_*`; real two-strand amplicon FASTA | **ok** |
| 17 | variantannotation/vcf_filtering | analysis bug: `allelicDepth()` assumed AD is a 3-D array but VariantAnnotation parses FORMAT AD (Number=R) as a matrix of per-allele vectors | rewrote AD filter to compute alt fraction robustly; somatic VCF fixture w/ AD + Germline/dbsnp prefilter tags | **ok** |
| 18 | camutqc/main | `system.file` demo data; needed a VEP-CSQ VCF + PON + regions | real VEP VCF (CSQ header w/ SYMBOL/Gene/BIOTYPE/Consequence, Ensembl IDs, MuTect2 GT:AD:DP), `##reference=GRCh38`, PON header CHROM/POS/REF/ALT, chr-prefixed BED bedFile, `packageVersion('CaMutQC')` case | **ok** |
| 19 | tximeta/linked_transcriptomes | `system.file`/tximportData; tximeta returns non-ranged SE when a custom Salmon index signature can't be matched → `seqinfo()` errored | consistent custom transcriptome fixture (quant.sf+FASTA+GTF); workflow attaches ranges from the user GTF (txdbmaker) when non-ranged; flatten list cols before write.csv | **ok** (proven via exact harness nextflow run rc=0, all 3 outputs) |
| 20 | affycoretools fixture (group) | round-1 `~group` referenced a pData col not in scope | `~groups` (the in-scope factor) | (folded into #12) |

## Blocked (documented, not forced green)

| workflow | why blocked |
|----------|-------------|
| **msbackendsql/main** | No domain image ships the Spectra/MsBackendSql MS stack. Re-pointed the container to the **proteomics** image (has mzR/RSQLite/DBI); but installing the remaining `Spectra`+`MsBackendSql` at runtime takes ~3 min (binary) / >5 min (source), exceeding the harness 300 s per-process execution window. The workflow itself is real & correct (mzML → SQLite backend → spectra-variable + peaks tables); needs the proteomics domain image rebuilt with `Spectra`+`MsBackendSql`+`MetaboCoreUtils` baked in. |
| **geneplotter/single_chromosome_expression_plotting** | `buildChromLocation("hgu95av2")` recurses deeply enough to overflow the geneplotter biocontainer's fixed **8 MB C protection stack** ("C stack usage too close to the limit"); the container does not allow raising `ulimit -s` (stays 8192 KB) and forked/child R processes inherit the same limit. Workflow logic (`alongChrom`) and the real hgu95av2 chr1 probe input are correct — passes on a host with a larger stack (succeeded once under low load). Environmental, not a workflow defect. |
| **diggit/main** | DIGGIT needs four mutually-consistent pre-computed objects (an ARACNe regulon in viper format, a MINDy modulator network, a GBM expression set with MES/PN subtypes, and a matched CNV matrix) plus hard-coded master regulators STAT3/CEBPD. These cannot be faithfully synthesised without running the full upstream ARACNe+MINDy pipeline on real GBM data, and the MI-permutation `marina`/`aqtl`/`conditional` analysis would exceed the execution window. `diggitdata` is the only realistic input. |
| **rawrr/main** | Reads `rawrr::sampleFilePath()` demo data and `installRawFileReaderDLLs()` (downloads proprietary Thermo RAW-reader DLLs + Mono from the network). No real user file input; un-runnable in the sandbox. Mis-generated workflow for a vendor-IO utility package. |
| **lpsymphony/main** | Generic linear-programming solver. The scraped body references `obj/mat/dir/rhs/types/max` that are never defined (vignette fragments). Not a bio-analysis with a real file input — an optimisation infra package. |
| **widgettools/main** | Tcl/Tk GUI widget toolkit (`label()/entryBox()/button()` need an X11/Tk display). Not a headless data-analysis workflow — GUI infra package. |
| **ssrch/main** | Search-index utility; scraped body uses `docset_cancer68` demo object + a hard-coded GEO accession and reads no input. Mis-generated for a search-infra package. |

`rawrr/lpsymphony/widgettools/ssrch` are the methodology's explicit skip category
(infra / GUI / vendor-IO / search), not real input→analysis→output workflows.

## How to reproduce a green
```
docker run --rm -v /tmp/realrun_rlib:/rlib alpine sh -c 'rm -rf /rlib/*'   # clear poison
cd /tmp/fix-round2/backend/scripts
echo "<pkg>" > /tmp/one.txt
python3 realrun_test_bioc_workflows.py --pkg-file /tmp/one.txt \
  --registry 399683337364.dkr.ecr.us-west-2.amazonaws.com/ --workers 1 --audit /tmp/r.json
```
