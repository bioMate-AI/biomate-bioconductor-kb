#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Cardinal
// Implements statistical & computational tools for analyzing mass spectrometry imaging datasets, inclu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Cardinal/inst/doc/Cardinal3-guide.R
// Upstream  : CardinalWorkflows
// Downstream: CardinalWorkflows
//
// Install: BiocManager::install("Cardinal")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CARDINAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cardinal"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cardinal:3.8.3--r44_0' :
        'quay.io/biocontainers/bioconductor-cardinal:3.8.3--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_cardinal_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cardinal_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cardinal_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MassDataFrame)
    library(jsonlite)

    # --- Phenotype data inspection [] ---
    # Key functions: exampleImzMLFile, readMSIData, spectraData, spectra, intensity, pixelData, pData, runNames
    mse_peaks2 <- as(mse_peaks2, "MSImagingExperiment")
    mse_peaks2 <- summarizeFeatures(mse_peaks2)
    plot(mse_peaks2, "mean", xlab="m/z", ylab="Intensity",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cardinal_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cardinal_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cardinal_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CARDINAL:", paste0("    cardinal: ", packageVersion("Cardinal"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cardinal_results.csv
    touch ${prefix}_cardinal_output.rds
    echo "BIOC_CARDINAL:" > versions.yml
    echo "    cardinal: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CARDINAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_CARDINAL(ch_input)

    emit:
    results  = BIOC_CARDINAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CARDINAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CARDINAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CARDINAL.out.versions  // channel: path(versions.yml)
}
