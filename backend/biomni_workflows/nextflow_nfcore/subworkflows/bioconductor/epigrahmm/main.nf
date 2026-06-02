#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epigraHMM
// epigraHMM provides a set of tools for the analysis of epigenomic data based on hidden Markov Models.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epigraHMM/inst/doc/epigraHMM.R
// Upstream  : GenomeInfoDb, GenomicRanges, SummarizedExperiment, gcapc, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("epigraHMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIGRAHMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epigrahmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epigrahmm:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epigrahmm:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epigrahmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epigrahmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epigrahmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epigraHMM)
    library(GRanges)
    library(jsonlite)

    # --- Normalization [] ---
    # Key functions: normalizeCounts, controlEM
    em_control <- controlEM(maxiter = 50,
                            tol = 1e-2,
                            verbose = FALSE)
    object <- normalizeCounts(object = object,
                              control = em_control)


    # --- Model Initialization [] ---
    # Key functions: initializer, controlEM
    em_control <- controlEM(maxiter = 50,
                            tol = 1e-2,
                            verbose = FALSE)
    object <- initializer(object = object,
                          control = em_control)


    # --- Consensus Peak Detection [] ---
    # Key functions: epigraHMM, controlEM
    em_control <- controlEM(maxiter = 50,
                            tol = 1e-2,
                            verbose = FALSE)
    object <- epigraHMM(object = object,
                        control = em_control,
                        type = 'consensus',
                        dist = 'zinb')


    # --- Peak Calling [] ---
    # Key functions: callPeaks, controlEM
    em_control <- controlEM(maxiter = 50,
                            tol = 1e-2,
                            verbose = FALSE)
    peaks <- callPeaks(object = object,
                       control = em_control,
                       method = 0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epigrahmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epigrahmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epigrahmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIGRAHMM:", paste0("    epigrahmm: ", packageVersion("epigraHMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epigrahmm_results.csv
    touch ${prefix}_epigrahmm_output.rds
    echo "BIOC_EPIGRAHMM:" > versions.yml
    echo "    epigrahmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIGRAHMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIGRAHMM(ch_input)

    emit:
    results  = BIOC_EPIGRAHMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIGRAHMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIGRAHMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIGRAHMM.out.versions  // channel: path(versions.yml)
}
