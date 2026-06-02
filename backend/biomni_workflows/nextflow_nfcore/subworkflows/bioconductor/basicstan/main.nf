#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BASiCStan
// Provides an interface to infer the parameters of BASiCS using the variational inference (ADVI), Mark
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BASiCStan/inst/doc/BASiCStan.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BASiCStan")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASICSTAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-basicstan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-basicstan:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-basicstan:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_basicstan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_basicstan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_basicstan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BASiCS_MCMC)
    library(BASiCS_ShowFit)
    library(BASiCStan)
    library(Stan2BASiCS)
    library(jsonlite)

    # --- Standard MCMC Estimation [] ---
    # Key functions: BASiCS_MCMC
    amwg_fit <- BASiCS_MCMC(
        sce,
        N = 200,
        Thin = 10,
        Burn = 100,
        Regression = TRUE
    )


    # --- Stan-based Parameter Estimation [] ---
    # Key functions: BASiCStan
    stan_fit <- BASiCStan(
        sce,
        Method = "sampling",
        iter = 10,
        warmup = 5,
        chains = 1
    )


    # --- Model Fit Comparison [] ---
    # Key functions: BASiCS_ShowFit
    # Display diagnostic summaries for the standard MCMC fit
    BASiCS_ShowFit(amwg_fit)
    # Display diagnostic summaries for the Stan-based fit
    BASiCS_ShowFit(stan_fit)


    # --- Raw Stan Object Extraction and Conversion [] ---
    # Key functions: BASiCStan, Stan2BASiCS
    stan_obj <- BASiCStan(
        sce,
        ReturnBASiCS = FALSE,
        Method = "sampling",
        iter = 10
    )
    converted_fit <- Stan2BASiCS(stan_obj)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_basicstan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_basicstan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_basicstan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASICSTAN:", paste0("    basicstan: ", packageVersion("BASiCStan"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basicstan_results.csv
    touch ${prefix}_basicstan_output.rds
    echo "BIOC_BASICSTAN:" > versions.yml
    echo "    basicstan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BASICSTAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BASICSTAN(ch_input)

    emit:
    results  = BIOC_BASICSTAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BASICSTAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BASICSTAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BASICSTAN.out.versions  // channel: path(versions.yml)
}
