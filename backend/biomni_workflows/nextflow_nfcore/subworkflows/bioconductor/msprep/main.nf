#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSPrep
// Package performs summarization of replicates, filtering by frequency, several different options for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSPrep/inst/doc/using_MSPrep.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MSPrep")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSPREP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msprep"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msprep:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msprep:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msprep_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msprep_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msprep_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSPrep)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(msquant)
    colnames(msquant)[3]
    # --- Mssummarize [] ---
    # Key functions: msSummarize
    ---------------------------------------------------------------------
    summarizedDF <- msSummarize(msquant,
                                cvMax = 0.50,
                                minPropPresent = 1/3,
                                compVars = c("mz", "rt"),
    # --- Msfilter [] ---
    # Key functions: msFilter
    ---------------------------------------------------------------------
    filteredDF <- msFilter(summarizedDF,
                           filterPercent = 0.8,
                           compVars = c("mz", "rt"),
                           sampleVars = c("spike", "batch", "subject_id"),
    # --- Msimpute [] ---
    # Key functions: msImpute
    ---------------------------------------------------------------------
    imputedDF <- msImpute(filteredDF,
                          imputeMethod = "knn",
                          compVars = c("mz", "rt"),
                          sampleVars = c("spike", "batch", "subject_id"),
    # --- Data [] ---
    # Key functions: msSummarize
    ---------------------------------------------------------------------
    data(COPD_131)
    summarizedSE131 <- msSummarize(COPD_131,
                                   cvMax = 0.5,
                                   minPropPresent = 1/3,
    # --- Msfilter [] ---
    # Key functions: msFilter
    ---------------------------------------------------------------------
    filteredSE131 <- msFilter(summarizedSE131,
                              filterPercent = 0.8)
    # --- Msimpute [] ---
    # Key functions: msImpute
    ---------------------------------------------------------------------
    imputedSE131 <- msImpute(filteredSE131,
                             imputeMethod = "bpca",
                             nPcs = 3,
                             missingValue = 0)
    # --- Msnormalize [] ---
    # Key functions: msNormalize
    ---------------------------------------------------------------------
    normalizedSe131 <- msNormalize(imputedSE131,
                                   normalizeMethod = "median",
                                   transform = "none")
    # --- Msprepare [] ---
    # Key functions: msPrepare
    ---------------------------------------------------------------------
    preparedSE <- msPrepare(COPD_131,
                            cvMax = 0.5,
                            minPropPresent = 1/3,
                            compVars = c("Mass", "Retention.Time",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msprep_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msprep_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msprep_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSPREP:", paste0("    msprep: ", packageVersion("MSPrep"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msprep_results.csv
    touch ${prefix}_msprep_output.rds
    echo "BIOC_MSPREP:" > versions.yml
    echo "    msprep: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSPREP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSPREP(ch_input)

    emit:
    results  = BIOC_MSPREP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSPREP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSPREP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSPREP.out.versions  // channel: path(versions.yml)
}
