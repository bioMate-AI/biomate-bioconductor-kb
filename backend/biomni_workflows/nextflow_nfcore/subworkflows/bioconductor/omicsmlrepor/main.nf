#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OmicsMLRepoR
// This package provides functions to browse the harmonized metadata for large omics databases. This pa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OmicsMLRepoR/inst/doc/Quickstart.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("OmicsMLRepoR")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_OMICSMLREPOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicsmlrepor"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicsmlrepor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicsmlrepor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicsmlrepor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("OmicsMLRepoR", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(OmicsMLRepoR)
    library(jsonlite)

    # --- tree_filter [] ---
    # Key functions: tree_filter, returnSamples, getLongMetaTb, getShortMetaTb
    cmd_sub <- tree_filter(cmd, target_condition, "Alzheimer's disease")
    tree_filter(col = "disease", "Type 2 Diabetes Mellitus") %>%
    filter(sex == "Female") %>%

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
        write.csv(as.data.frame(.main), "${prefix}_omicsmlrepor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_omicsmlrepor_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_omicsmlrepor_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICSMLREPOR:", paste0("    omicsmlrepor: ", as.character(packageVersion("OmicsMLRepoR")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicsmlrepor_results.csv
    touch ${prefix}_omicsmlrepor_output.rds
    echo "BIOC_OMICSMLREPOR:" > versions.yml
    echo "    omicsmlrepor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICSMLREPOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICSMLREPOR(ch_input)

    emit:
    results  = BIOC_OMICSMLREPOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICSMLREPOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICSMLREPOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICSMLREPOR.out.versions  // channel: path(versions.yml)
}
