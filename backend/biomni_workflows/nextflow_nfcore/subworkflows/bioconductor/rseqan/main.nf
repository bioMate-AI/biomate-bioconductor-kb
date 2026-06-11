#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RSeqAn
// Headers and some wrapper functions from the SeqAn C++ library for ease of usage in R.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RSeqAn/inst/doc/first_example.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RSeqAn")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_RSEQAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rseqan"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rseqan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rseqan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rseqan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RSeqAn)
    library(jsonlite)

    # --- ps r [] ---
    # Key functions: pattern_search
    pattern_search("This is an awesome tutorial to get to know SeqAn!", "tutorial")

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
        write.csv(as.data.frame(.main), "${prefix}_rseqan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rseqan_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rseqan_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSEQAN:", paste0("    rseqan: ", as.character(packageVersion("RSeqAn")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rseqan_results.csv
    touch ${prefix}_rseqan_output.rds
    echo "BIOC_RSEQAN:" > versions.yml
    echo "    rseqan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSEQAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSEQAN(ch_input)

    emit:
    results  = BIOC_RSEQAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSEQAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSEQAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSEQAN.out.versions  // channel: path(versions.yml)
}
