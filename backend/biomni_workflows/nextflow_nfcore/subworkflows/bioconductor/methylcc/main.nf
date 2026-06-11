#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylCC
// A tool to estimate the cell composition of DNA methylation whole blood sample measured on any platfo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylCC/inst/doc/methylCC.R
// Upstream  : dplyr, ggplot2, minfi, tidyr
// Downstream: none
//
// Install: BiocManager::install("methylCC")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_METHYLCC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylcc"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylcc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylcc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylcc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylCC)
    library(jsonlite)

    # --- Data Preparation [] ---
    # Key functions: pData
    rgset <- FlowSorted.Blood.450k[,
        pData(FlowSorted.Blood.450k)\$CellTypeLong %in% "Whole blood"
    ]
    sampleNames(rgset) <- paste0("Sample", seq_len(ncol(rgset)))

    # --- Cell Composition Estimation [] ---
    # Key functions: estimatecc
    est <- estimatecc(
        object = rgset,
        findRegions = TRUE
    )

    # --- Cell Counts Extraction [] ---
    # Key functions: cell_counts
    counts <- cell_counts(est)
    summary_counts <- summary(counts)

    # --- Comparison with Minfi [] ---
    # Key functions: cell_counts
    est_minfi <- minfi::estimateCellCounts(rgset)
    df_minfi <- as.data.frame(est_minfi)
    df_methylcc <- as.data.frame(cell_counts(est))


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
        write.csv(as.data.frame(.main), "${prefix}_methylcc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_methylcc_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_methylcc_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLCC:", paste0("    methylcc: ", as.character(packageVersion("methylCC")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylcc_results.csv
    touch ${prefix}_methylcc_output.rds
    echo "BIOC_METHYLCC:" > versions.yml
    echo "    methylcc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLCC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLCC(ch_input)

    emit:
    results  = BIOC_METHYLCC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLCC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLCC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLCC.out.versions  // channel: path(versions.yml)
}
