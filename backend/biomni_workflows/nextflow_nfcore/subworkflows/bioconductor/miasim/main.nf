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

    # --- Anormal [] ---
    # Key functions: powerlawA
    A_normal <- powerlawA(n_species = 4, alpha = 3)
    # --- Auniform [] ---
    # Key functions: randomA
    A_uniform <- randomA(n_species = 10,
    interactions = runif(n = 10^2, min = -0.8, max = 0.8))
    # --- simulate Ricker [] ---
    # Key functions: simulateRicker, simulateHubbell, simulateHubbellRates, simulateSOI, simulateStochasticLogistic
    tse_ricker <- simulateRicker(n_species=4, A = A_normal, t_end=100, norm = FALSE)
    tse_hubbell <- simulateHubbell(n_species = 8,
    params_hubbell <- simulateHubbellRates(x0 = c(0,5,10),
    # --- simulate Consumer Resource [] ---
    # Key functions: simulateConsumerResource
    tse_crm <- simulateConsumerResource(n_species = 2,
    E = randomE(n_species = 2, n_resources = 4))
    # --- simulate G L V [] ---
    # Key functions: simulateGLV, plotAbundanceDensity, plotSeries
    tse_glv <- simulateGLV(n_species = 4,
    library(miaViz)
    p1 <- plotAbundanceDensity(tse_hubbell, assay.type = "counts")

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
