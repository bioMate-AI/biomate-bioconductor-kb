#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rfPred
// Based on external numerous data files where rfPred scores are pre-calculated on all genomic position
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rfPred/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rfPred")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_RFPRED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rfpred"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rfpred_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rfpred_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rfpred_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("rfPred", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(rfPred)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(variant_list_Y)
    print(variant_list_Y)
    # --- Rfpred Scores [] ---
    # Key functions: rfPred_scores
    result=rfPred_scores(variant_list=variant_list_Y,
                         data=system.file("extdata/chrY_rfPred.txtz", package="rfPred"),
                         index=system.file("extdata/chrY_rfPred.txtz.tbi", package="rfPred"))
    print(result)

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
        write.csv(as.data.frame(.main), "${prefix}_rfpred_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rfpred_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rfpred_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RFPRED:", paste0("    rfpred: ", as.character(packageVersion("rfPred")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rfpred_results.csv
    touch ${prefix}_rfpred_output.rds
    echo "BIOC_RFPRED:" > versions.yml
    echo "    rfpred: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RFPRED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RFPRED(ch_input)

    emit:
    results  = BIOC_RFPRED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RFPRED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RFPRED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RFPRED.out.versions  // channel: path(versions.yml)
}
