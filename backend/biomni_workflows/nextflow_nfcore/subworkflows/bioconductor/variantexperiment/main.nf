#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VariantExperiment
// VariantExperiment is a Bioconductor package for saving data in VCF/GDS format into RangedSummarizedE
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VariantExperiment/inst/doc/VariantExperiment-class.R
// Upstream  : GDSArray
// Downstream: none
//
// Install: BiocManager::install("VariantExperiment")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_VARIANTEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-variantexperiment"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_variantexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_variantexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_variantexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("VariantExperiment", "GDSArray", "jsonlite", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    lib    library(SummarizedExperiment)
rary(VariantExperiment)
    library(GDSArray)
    library(jsonlite)

    # --- Data Import and Initialization [VariantExperiment] ---
    # Key functions: showAvailable, makeVariantExperimentFromGDS, makeVariantExperimentFromVCF
    gds_file <- SeqArray::seqExampleFileName("gds")
    avail_nodes <- showAvailable(gds_file)
    ve <- makeVariantExperimentFromGDS(
        gds_file,
        rowDataColumns = c("allele", "annotation/id"),
        infoColumns = c("AC", "AN", "DP"),
        rowDataOnDisk = TRUE,
        colDataOnDisk = FALSE
    )

    # --- Metadata and Annotation Extraction [VariantExperiment] ---
    # Key functions: gdsfile, makeVariantExperimentFromVCF
    gds_path <- gdsfile(ve)
    variant_info <- rowData(ve)
    sample_info <- colData(ve)
    vcf_file <- SeqArray::seqExampleFileName("vcf")
    ve_vcf <- makeVariantExperimentFromVCF(
        vcf_file,
        start = 101,
        count = 1000
    )

    # --- Genomic Filtering and Subsetting [VariantExperiment] ---
    # Key functions: subsetByOverlaps
    target_region <- GenomicRanges::GRanges("22:1-48958933")
    ve_filtered <- subsetByOverlaps(ve, target_region)
    ref_t_idx <- as.logical(rowData(ve_filtered)\$REF == "T")
    ve_subset <- ve_filtered[ref_t_idx, ]

    # --- Data Serialization and Persistence [VariantExperiment] ---
    # Key functions: saveVariantExperiment, loadVariantExperiment
    out_dir <- tempfile()
    ve_saved <- saveVariantExperiment(
        ve_filtered,
        dir = out_dir,
        replace = TRUE,
        chunk_size = 30
    )
    ve_loaded <- loadVariantExperiment(dir = out_dir)


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_variantexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_variantexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_variantexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_VARIANTEXPERIMENT:", paste0("    variantexperiment: ", as.character(packageVersion("VariantExperiment")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variantexperiment_results.csv
    touch ${prefix}_variantexperiment_output.rds
    echo "BIOC_VARIANTEXPERIMENT:" > versions.yml
    echo "    variantexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VARIANTEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VARIANTEXPERIMENT(ch_input)

    emit:
    results  = BIOC_VARIANTEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VARIANTEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VARIANTEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VARIANTEXPERIMENT.out.versions  // channel: path(versions.yml)
}
