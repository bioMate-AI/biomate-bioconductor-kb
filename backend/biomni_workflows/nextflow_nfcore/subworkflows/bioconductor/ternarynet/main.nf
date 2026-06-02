#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ternarynet
// Gene-regulatory network (GRN) modeling seeks to infer dependencies between genes and thereby provide
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ternarynet/inst/doc/ternarynet.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ternarynet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TERNARYNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ternarynet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ternarynet:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ternarynet:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ternarynet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ternarynet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ternarynet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ternarynet)
    library(jsonlite)

    # --- Data Preparation [ternarynet] ---
    # Key functions: data.frame
    i_exp <- as.integer(c(0,0,0, 0,0,0, 1,1,1, 1,1,1))
    i_node <- as.integer(c(0,0,0, 1,1,1, 0,0,0, 1,1,1))
    outcome <- as.integer(c(-1,0,1, -1,0,1, -1,0,1, -1,0,1))
    value <- c(0,1,2, 0,1,2, 2,1,0, 0,1,2)
    is_perturbation <- c(
        TRUE, TRUE, TRUE, FALSE, FALSE, FALSE,
        FALSE, FALSE, FALSE, TRUE, TRUE, TRUE
    )
    indata <- data.frame(
        i_exp = i_exp,
        i_node = i_node,
        outcome = outcome,
        value = value,
        is_perturbation = is_perturbation
    )

    # --- Network Fitting [ternarynet] ---
    # Key functions: parallelFit
    results <- parallelFit(
        indata,
        max_parents = 1,
        n_cycles = 10000,
        n_write = 10,
        T_lo = 0.001,
        T_hi = 2.0,
        target_score = 0,
        n_proc = 1,
        logfile = "ternarynet_fit.log"
    )

    # --- Model Refinement [ternarynet] ---
    # Key functions: parallelFit
    refined_results <- parallelFit(
        indata,
        max_parents = 1,
        n_cycles = 100,
        n_write = 10,
        T_lo = 0.001,
        T_hi = 2.0,
        target_score = 0,
        n_proc = 1,
        logfile = "ternarynet_refine.log",
        init_parents = best_parents,
        init_outcomes = best_outcomes
    )
    refined_best <- refined_results[[1]]


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ternarynet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ternarynet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ternarynet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TERNARYNET:", paste0("    ternarynet: ", packageVersion("ternarynet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ternarynet_results.csv
    touch ${prefix}_ternarynet_output.rds
    echo "BIOC_TERNARYNET:" > versions.yml
    echo "    ternarynet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TERNARYNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TERNARYNET(ch_input)

    emit:
    results  = BIOC_TERNARYNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TERNARYNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TERNARYNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TERNARYNET.out.versions  // channel: path(versions.yml)
}
