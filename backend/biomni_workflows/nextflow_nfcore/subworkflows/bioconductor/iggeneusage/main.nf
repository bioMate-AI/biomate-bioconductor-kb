#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IgGeneUsage
// Detection of biases in the usage of immunoglobulin (Ig) genes is an important task in immune reperto
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IgGeneUsage/inst/doc/User_Manual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("IgGeneUsage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IGGENEUSAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iggeneusage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iggeneusage:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iggeneusage:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iggeneusage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iggeneusage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iggeneusage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGU)
    library(LOO)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, kable
    ---------------------------------------------------------------------
    data("d_zibb_3", package = "IgGeneUsage")
    knitr::kable(head(d_zibb_3))
    # --- Dgu [] ---
    # Key functions: DGU, chain, run, level, rate, step
    ---------------------------------------------------------------------
    M <- DGU(ud = d_zibb_3, # input data
             mcmc_warmup = 300, # how many MCMC warm-ups per chain (default: 500)
             mcmc_steps = 1500, # how many MCMC steps per chain (default: 1,500)
             mcmc_chains = 3, # how many MCMC chain to run (default: 4)
    # --- Check Hmc Diagnostics [] ---
    # Key functions: check_hmc_diagnostics
    ---------------------------------------------------------------------
    rstan::check_hmc_diagnostics(M$fit)
    # --- Kable [] ---
    # Key functions: kable
    ---------------------------------------------------------------------
    kable(x = head(M$dgu), row.names = FALSE, digits = 2)
    # --- Loo [] ---
    # Key functions: LOO, chain, run, level, rate, step
    ---------------------------------------------------------------------
    L <- LOO(ud = d_zibb_3, # input data
             mcmc_warmup = 500, # how many MCMC warm-ups per chain (default: 500)
             mcmc_steps = 1000, # how many MCMC steps per chain (default: 1,500)
             mcmc_chains = 1, # how many MCMC chain to run (default: 4)
    # --- Call [] ---
    # Key functions: call
    ---------------------------------------------------------------------
    L_gu <- do.call(rbind, lapply(X = L, FUN = function(x){return(x$gu)}))
    L_dgu <- do.call(rbind, lapply(X = L, FUN = function(x){return(x$dgu)}))
    # --- Data [] ---
    # Key functions: data, kable
    ---------------------------------------------------------------------
    data("d_zibb_4", package = "IgGeneUsage")
    knitr::kable(head(d_zibb_4))
    # --- Dgu [] ---
    # Key functions: DGU, chain, run, level, rate, step
    ---------------------------------------------------------------------
    M <- DGU(ud = d_zibb_4, # input data
             mcmc_warmup = 500, # how many MCMC warm-ups per chain (default: 500)
             mcmc_steps = 1500, # how many MCMC steps per chain (default: 1,500)
             mcmc_chains = 2, # how many MCMC chain to run (default: 4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iggeneusage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iggeneusage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iggeneusage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IGGENEUSAGE:", paste0("    iggeneusage: ", packageVersion("IgGeneUsage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iggeneusage_results.csv
    touch ${prefix}_iggeneusage_output.rds
    echo "BIOC_IGGENEUSAGE:" > versions.yml
    echo "    iggeneusage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IGGENEUSAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IGGENEUSAGE(ch_input)

    emit:
    results  = BIOC_IGGENEUSAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IGGENEUSAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IGGENEUSAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IGGENEUSAGE.out.versions  // channel: path(versions.yml)
}
