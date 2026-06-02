#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rain
// This package uses non-parametric methods to detect rhythms in time series. It deals with outliers, m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rain/inst/doc/rain.R
// Upstream  : lattice
// Downstream: none
//
// Install: BiocManager::install("rain")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rain"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rain:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rain:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rain_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rain_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rain_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rain)
    library(jsonlite)

    # --- Rain [] ---
    # Key functions: rain
    require(rain)
    rainresult <- rain(measure, period=24,
                    deltat=2, peak.border=c(0.1,0.9),
                    verbose=FALSE
    )
    # --- Data [] ---
    # Key functions: data
    data(menetRNASeqMouseLiver)
    colnames(menetRNASeqMouseLiver)
    # --- Rain [] ---
    # Key functions: rain, xyplot
    results <- rain(t(menetRNASeqMouseLiver), deltat=4, period=24, nr.series=2,
                    peak.border=c(0.3, 0.7), verbose=FALSE)
    best <- order(results$pVal)[1:10]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rain_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rain_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rain_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAIN:", paste0("    rain: ", packageVersion("rain"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rain_results.csv
    touch ${prefix}_rain_output.rds
    echo "BIOC_RAIN:" > versions.yml
    echo "    rain: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAIN(ch_input)

    emit:
    results  = BIOC_RAIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAIN.out.versions  // channel: path(versions.yml)
}
