#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ExperimentSubset
// Experiment objects such as the SummarizedExperiment or SingleCellExperiment are data containers for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ExperimentSubset/inst/doc/ExperimentSubset.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ExperimentSubset")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_EXPERIMENTSUBSET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-experimentsubset"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_experimentsubset_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_experimentsubset_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_experimentsubset_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentSubset)
    library(jsonlite)

    # --- Object Initialization [] ---
    # Key functions: ExperimentSubset
    counts_matrix <- matrix(rpois(100, lambda = 10), ncol = 10, nrow = 10)
    sce_obj <- SingleCellExperiment::SingleCellExperiment(
        assays = list(counts = counts_matrix)
    )
    es <- ExperimentSubset(sce_obj)

    # --- Subset Creation [] ---
    # Key functions: createSubset
    es <- createSubset(
        es,
        subsetName = "subset1",
        rows = c(1:5),
        cols = c(1:5),
        parentAssay = "counts"
    )

    # --- Subset Assay Management [] ---
    # Key functions: setSubsetAssay, getSubsetAssay, assay
    subset1_assay <- assay(es, "subset1")
    subset1_assay[,] <- subset1_assay[,] + 1
    es <- setSubsetAssay(
        es,
        subsetName = "subset1",
        inputMatrix = subset1_assay,
        subsetAssayName = "subset1Assay"
    )
    internal_assay <- getSubsetAssay(es, "subset1Assay")

    # --- Metadata Management [] ---
    # Key functions: subsetColData, subsetColData<-, subsetDim
    subsetColData(es, "subset1") <- cbind(
        subsetColData(es, "subset1"),
        subsetSampleID = seq_len(subsetDim(es, "subset1")[2])
    )
    sub_col_data <- subsetColData(es, "subset1", parentColData = TRUE)

    # --- Alternative Experiments and Summarization [] ---
    # Key functions: altExp<-, subsetSummary
    SingleCellExperiment::altExp(
        x = es,
        e = "subset1_alt",
        subsetName = "subset1"
    ) <- SingleCellExperiment::SingleCellExperiment(
        assay = list(counts = assay(es, "subset1"))
    )
    summary_table <- subsetSummary(es)


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
        write.csv(as.data.frame(.main), "${prefix}_experimentsubset_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_experimentsubset_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_experimentsubset_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_EXPERIMENTSUBSET:", paste0("    experimentsubset: ", as.character(packageVersion("ExperimentSubset")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_experimentsubset_results.csv
    touch ${prefix}_experimentsubset_output.rds
    echo "BIOC_EXPERIMENTSUBSET:" > versions.yml
    echo "    experimentsubset: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EXPERIMENTSUBSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EXPERIMENTSUBSET(ch_input)

    emit:
    results  = BIOC_EXPERIMENTSUBSET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EXPERIMENTSUBSET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EXPERIMENTSUBSET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EXPERIMENTSUBSET.out.versions  // channel: path(versions.yml)
}
