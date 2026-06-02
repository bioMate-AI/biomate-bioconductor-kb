#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mnem
// Mixture Nested Effects Models (mnem) is an extension of Nested Effects Models and allows for the ana
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mnem/inst/doc/mnem.R
// Upstream  : none
// Downstream: nempi
//
// Install: BiocManager::install("mnem")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MNEM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mnem"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mnem:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mnem:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mnem_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mnem_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mnem_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mnem)
    library(jsonlite)

    # --- Data Simulation [Simulation] ---
    # Key functions: simData
    simmini <- simData(
        Sgenes = 3,
        Egenes = 10,
        Nems = 3,
        mw = c(0.4, 0.3, 0.3),
        nCells = 100,
        uninform = 1,
        multi = c(0.2, 0.1)
    )
    sim_data <- simmini$data
    ones <- which(sim_data == 1)
    zeros <- which(sim_data == 0)
    sim_data[ones] <- rnorm(length(ones), 1, 0.5)
    sim_data[zeros] <- rnorm(length(zeros), -1, 0.5)

    # --- Model Selection [Inference] ---
    # Key functions: mnemk
    bestk <- mnemk(
        sim_data,
        ks = 1:3,
        search = "greedy",
        starts = 3,
        parallel = NULL
    )
    best_model <- bestk$best
    log_likelihoods <- bestk$lls
    penalized_ics <- bestk$ics

    # --- Mixture NEM Inference [Inference] ---
    # Key functions: mnem
    result_continuous <- mnem(
        sim_data,
        k = 3,
        search = "greedy",
        starts = 3,
        method = "cont"
    )
    result_discrete <- mnem(
        sim_data,
        k = 3,
        search = "greedy",
        starts = 3,
        method = "disc",
        fpfn = c(0.1, 0.1)
    )

    # --- Model Evaluation and Diagnostics [Diagnostics] ---
    # Key functions: getAffinity, fitacc, plotConvergence
    post_probs <- getAffinity(
        best_model$probs,
        mw = best_model$mw
    )
    accuracy <- fitacc(
        best_model,
        simmini,
        strict = TRUE
    )
    plotConvergence(
        best_model,
        cex.main = 0.7,
        cex.lab = 0.7
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mnem_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mnem_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mnem_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MNEM:", paste0("    mnem: ", packageVersion("mnem"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mnem_results.csv
    touch ${prefix}_mnem_output.rds
    echo "BIOC_MNEM:" > versions.yml
    echo "    mnem: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MNEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MNEM(ch_input)

    emit:
    results  = BIOC_MNEM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MNEM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MNEM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MNEM.out.versions  // channel: path(versions.yml)
}
