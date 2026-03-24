#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lpsymphony
// This package was derived from Rsymphony_0.1-17 from CRAN. These packages provide an R interface to S
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lpsymphony/inst/doc/lpsymphony.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("lpsymphony")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LPSYMPHONY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lpsymphony"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lpsymphony:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lpsymphony:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lpsymphony_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lpsymphony_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lpsymphony_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(lpsymphony)
    library(jsonlite)

    # --- Style Knitr [] ---
    # Key functions: latex
    ----------------
    BiocStyle::latex()
    # --- Lpsymphony Solve Lp [] ---
    # Key functions: lpsymphony_solve_LP
    ------------------------------------------------------------------
    lpsymphony_solve_LP(obj, mat, dir, rhs, types = types, max = max)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lpsymphony_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lpsymphony_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lpsymphony_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LPSYMPHONY:", paste0("    lpsymphony: ", packageVersion("lpsymphony"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lpsymphony_results.csv
    touch ${prefix}_lpsymphony_output.rds
    echo "BIOC_LPSYMPHONY:" > versions.yml
    echo "    lpsymphony: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LPSYMPHONY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LPSYMPHONY(ch_input)

    emit:
    results  = BIOC_LPSYMPHONY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LPSYMPHONY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LPSYMPHONY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LPSYMPHONY.out.versions  // channel: path(versions.yml)
}
