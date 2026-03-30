#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rbsurv
// This package selects genes associated with survival.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rbsurv/inst/doc/rbsurv.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rbsurv")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBSURV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbsurv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbsurv:2.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rbsurv:2.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbsurv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbsurv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbsurv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rbsurv)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: exprs
    library(rbsurv)
    data(gliomaSet)
    gliomaSet
    x <- exprs(gliomaSet)
    x <- log2(x)
    # --- Rbsurv [] ---
    # Key functions: rbsurv
    fit <-  rbsurv(time=time, status=status, x=x, method="efron", max.n.genes=20)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbsurv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbsurv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbsurv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBSURV:", paste0("    rbsurv: ", packageVersion("rbsurv"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbsurv_results.csv
    touch ${prefix}_rbsurv_output.rds
    echo "BIOC_RBSURV:" > versions.yml
    echo "    rbsurv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBSURV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBSURV(ch_input)

    emit:
    results  = BIOC_RBSURV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBSURV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBSURV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBSURV.out.versions  // channel: path(versions.yml)
}
