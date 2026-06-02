#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miaSim
// Microbiome time series simulation with generalized Lotka-Volterra model, Self-Organized Instability 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miaSim/inst/doc/miaSim.R
// Upstream  : miaViz
// Downstream: none
//
// Install: BiocManager::install("miaSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIASIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-miasim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-miasim:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-miasim:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_miasim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_miasim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_miasim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(miaSim)
    library(jsonlite)

    # --- Interaction Matrix Generation [Simulation] ---
    # Key functions: powerlawA, randomA, randomE
    A_normal <- powerlawA(n_species = 10, alpha = 3)
    A_uniform <- randomA(
        n_species = 10,
        diagonal = -0.4,
        connectance = 0.5,
        interactions = runif(n = 100, min = -0.8, max = 0.8)
    )
    E_matrix <- randomE(n_species = 5, n_resources = 10)

    # --- Lotka-Volterra and Ricker Simulation [Simulation] ---
    # Key functions: powerlawA, simulateGLV, simulateRicker
    A_normal <- powerlawA(n_species = 4, alpha = 3)
    tse_glv <- simulateGLV(
        n_species = 4,
        A = A_normal,
        t_start = 0,
        t_store = 1000,
        stochastic = FALSE,
        norm = FALSE
    )
    tse_ricker <- simulateRicker(
        n_species = 4,
        A = A_normal,
        t_end = 100,
        norm = FALSE
    )

    # --- Hubbell Neutral Model Simulation [Simulation] ---
    # Key functions: simulateHubbell, simulateHubbellRates
    tse_hubbell <- simulateHubbell(
        n_species = 8,
        M = 10,
        carrying_capacity = 1000,
        k_events = 50,
        migration_p = 0.02,
        t_end = 100
    )
    params_hubbell <- simulateHubbellRates(
        x0 = c(0, 5, 10),
        migration_p = 0.1,
        metacommunity_probability = NULL,
        k_events = 1,
        growth_rates = NULL,
        norm = FALSE,
        t_end = 1000
    )

    # --- Stochastic Logistic and Consumer-Resource Simulation [Simulation] ---
    # Key functions: powerlawA, randomE, simulateStochasticLogistic, simulateConsumerResource, simulateSOI
    A_normal <- powerlawA(n_species = 4, alpha = 3)
    E_matrix <- randomE(n_species = 2, n_resources = 4)
    tse_logistic <- simulateStochasticLogistic(n_species = 5)
    tse_crm <- simulateConsumerResource(
        n_species = 2,
        n_resources = 4,
        E = E_matrix
    )
    tse_soi <- simulateSOI(
        n_species = 4,
        carrying_capacity = 1000,
        A = A_normal,
        k_events = 5,
        x0 = NULL,
        t_end = 150,
        norm = TRUE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_miasim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_miasim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_miasim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIASIM:", paste0("    miasim: ", packageVersion("miaSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_miasim_results.csv
    touch ${prefix}_miasim_output.rds
    echo "BIOC_MIASIM:" > versions.yml
    echo "    miasim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIASIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIASIM(ch_input)

    emit:
    results  = BIOC_MIASIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIASIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIASIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIASIM.out.versions  // channel: path(versions.yml)
}
