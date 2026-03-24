#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: granulator
// granulator is an R package for the cell type deconvolution of heterogeneous tissues based on bulk RN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/granulator/inst/doc/granulator.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("granulator")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRANULATOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-granulator"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-granulator:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-granulator:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_granulator_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_granulator_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_granulator_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(granulator)
    library(jsonlite)

    # --- Proportions [] ---
    # Key functions: proportions
    ---------------------------------------------------------------------
    # print measured cell type proportions (percentages)
    groundTruth_ABIS[1:5, 1:5]
    # --- Benchmark [] ---
    # Key functions: benchmark
    ---------------------------------------------------------------------
    # benchmark methods by correlating estimated to measured cell type proportions
    bench <- benchmark(deconvoluted = decon, ground_truth = groundTruth_ABIS)
    # --- Correlate [] ---
    # Key functions: correlate
    ---------------------------------------------------------------------
    # correlation analysis
    correl <- correlate(deconvoluted = decon)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_granulator_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_granulator_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_granulator_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GRANULATOR:", paste0("    granulator: ", packageVersion("granulator"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_granulator_results.csv
    touch ${prefix}_granulator_output.rds
    echo "BIOC_GRANULATOR:" > versions.yml
    echo "    granulator: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GRANULATOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GRANULATOR(ch_input)

    emit:
    results  = BIOC_GRANULATOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GRANULATOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GRANULATOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GRANULATOR.out.versions  // channel: path(versions.yml)
}
