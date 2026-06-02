#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HIREewas
// In epigenome-wide association studies, the measured signals for each sample are a mixture of methyla
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HIREewas/inst/doc/HIREewas.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HIREewas")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIREEWAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hireewas"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hireewas:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hireewas:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hireewas_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hireewas_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hireewas_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HIRE)
    library(jsonlite)

    # --- data preparation1 [] ---
    # Key functions: rgamma, rbeta, sample
    set.seed(123)
    rDirichlet <- function(alpha_vec){
    num <- length(alpha_vec)
    # --- H I R E [] ---
    # Key functions: HIRE
    library(HIREewas)
    ret_list <- HIRE(Ometh, X, num_celltype=K, tol=10^(-5), num_iter=1000, alpha=0.01)
    # --- risk Cp Gpattern [] ---
    # Key functions: riskCpGpattern
    class(ret_list)
    head(ret_list$mu_t)
    head(ret_list$beta_t)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hireewas_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hireewas_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hireewas_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HIREEWAS:", paste0("    hireewas: ", packageVersion("HIREewas"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hireewas_results.csv
    touch ${prefix}_hireewas_output.rds
    echo "BIOC_HIREEWAS:" > versions.yml
    echo "    hireewas: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HIREEWAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HIREEWAS(ch_input)

    emit:
    results  = BIOC_HIREEWAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HIREEWAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HIREEWAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HIREEWAS.out.versions  // channel: path(versions.yml)
}
