#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.sce
// Save SingleCellExperiment into file artifacts, and load them back into memory. This is a more portab
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.sce/inst/doc/userguide.R
// Upstream  : BiocStyle, SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("alabaster.sce")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ALABASTER_SCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_sce"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_sce_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_sce_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_sce_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(alabaster.sce)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rpois
    ---------------------------------------------------------------------
    mat <- matrix(rpois(10000, 10), ncol=10)
    colnames(mat) <- letters[1:10]
    rownames(mat) <- sprintf("GENE_%i", seq_len(nrow(mat)))
    # --- Readobject [] ---
    # Key functions: readObject
    ---------------------------------------------------------------------
    roundtrip <- readObject(tmp)
    class(roundtrip)

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
        write.csv(as.data.frame(.main), "${prefix}_alabaster_sce_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_alabaster_sce_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_alabaster_sce_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_SCE:", paste0("    alabaster_sce: ", as.character(packageVersion("alabaster.sce")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_sce_results.csv
    touch ${prefix}_alabaster_sce_output.rds
    echo "BIOC_ALABASTER_SCE:" > versions.yml
    echo "    alabaster_sce: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_SCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_SCE(ch_input)

    emit:
    results  = BIOC_ALABASTER_SCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_SCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_SCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_SCE.out.versions  // channel: path(versions.yml)
}
