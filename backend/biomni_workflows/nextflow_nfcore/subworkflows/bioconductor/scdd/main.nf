#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scDD
// This package implements a method to analyze single-cell RNA- seq Data utilizing flexible Dirichlet P
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scDD/inst/doc/scDD.R
// Upstream  : SingleCellExperiment, gridExtra
// Downstream: none
//
// Install: BiocManager::install("scDD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCDD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scdd"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scdd:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scdd:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scdd_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scdd_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scdd_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scDD)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Data Preprocessing [preprocess] ---
    # Key functions: preprocess
    data(scDatEx)
    scDatEx_filtered <- preprocess(scDatEx, zero.thresh=0.9)
    scDatEx_scran <- preprocess(scDatEx, zero.thresh=0.5, scran_norm=TRUE)

    # --- Dataset Simulation [simulateSet] ---
    # Key functions: simulateSet
    data(scDatEx)
    simulated_set <- simulateSet(scDatEx, numSamples=50, 
                                 nDE=5, nDP=5, nDM=5, nDB=5, 
                                 nEE=5, nEP=5, sd.range=c(2,2), 
                                 modeFC=4, plots=FALSE, 
                                 random.seed=816)

    # --- Differential Distribution Analysis [scDD] ---
    # Key functions: scDD, results
    data(scDatExSim)
    prior_param <- list(alpha=0.01, mu0=0, s0=0.01, a0=0.01, b0=0.01)
    scDatExSim_analyzed <- scDD(scDatExSim, prior_param=prior_param, 
                                testZeroes=FALSE, permutations=10)
    res_table <- results(scDatExSim_analyzed)
    partition_c1 <- results(scDatExSim_analyzed, type="Zhat.c1")

    # --- Visualisation [sideViolin] ---
    # Key functions: sideViolin
    data(scDatExSim)
    de_violin <- sideViolin(SingleCellExperiment::normcounts(scDatExSim)[1,], 
                            scDatExSim$condition, 
                            title.gene=rownames(scDatExSim)[1])
    dp_violin <- sideViolin(SingleCellExperiment::normcounts(scDatExSim)[6,], 
                            scDatExSim$condition, 
                            title.gene=rownames(scDatExSim)[6])


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scdd_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scdd_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scdd_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCDD:", paste0("    scdd: ", packageVersion("scDD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scdd_results.csv
    touch ${prefix}_scdd_output.rds
    echo "BIOC_SCDD:" > versions.yml
    echo "    scdd: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCDD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCDD(ch_input)

    emit:
    results  = BIOC_SCDD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCDD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCDD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCDD.out.versions  // channel: path(versions.yml)
}
