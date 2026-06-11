#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChemmineOB
// ChemmineOB provides an R interface to a subset of cheminformatics functionalities implemented by the
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/ChemmineOB/inst/doc/ChemmineOB.html
// Upstream  : ChemmineR
// Downstream: none
//
// Install: BiocManager::install("ChemmineOB")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_CHEMMINEOB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chemmineob"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chemmineob_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chemmineob_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chemmineob_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OBDescriptor_GetStringValue)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: requireNamespace, packages
    if (!requireNamespace("BiocManager", quietly=TRUE))
        install.packages("BiocManager")
    BiocManager::install(c("ChemmineR", "ChemmineOB"))
    library("ChemmineR")
    library("ChemmineOB")
    # --- Code Block 3 [] ---
    # Key functions: stringp, OBDescriptor_GetStringValue, cast, value
    result = stringp()
    OBDescriptor_GetStringValue(... , result\$cast())
    stringValue = result\$value()

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
        write.csv(as.data.frame(.main), "${prefix}_chemmineob_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_chemmineob_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_chemmineob_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHEMMINEOB:", paste0("    chemmineob: ", as.character(packageVersion("ChemmineOB")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chemmineob_results.csv
    touch ${prefix}_chemmineob_output.rds
    echo "BIOC_CHEMMINEOB:" > versions.yml
    echo "    chemmineob: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHEMMINEOB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHEMMINEOB(ch_input)

    emit:
    results  = BIOC_CHEMMINEOB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHEMMINEOB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHEMMINEOB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHEMMINEOB.out.versions  // channel: path(versions.yml)
}
