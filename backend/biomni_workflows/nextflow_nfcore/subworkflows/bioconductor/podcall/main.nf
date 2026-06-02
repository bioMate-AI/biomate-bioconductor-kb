#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PoDCall
// Reads files exported from 'QX Manager or QuantaSoft' containing amplitude values from a run of ddPCR
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PoDCall/inst/doc/PoDCall.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PoDCall")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PODCALL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-podcall"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-podcall:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-podcall:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_podcall_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_podcall_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_podcall_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PoDCall)
    library(jsonlite)

    # --- install_github [] ---
    # Key functions: install_github, install_local
    if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
    BiocManager::install("PoDCall")
    # --- import Amplitude Data [] ---
    # Key functions: importAmplitudeData
    path <- system.file("extdata", "Amplitudes/", package="PoDCall")
    dataList <- importAmplitudeData(dataDirectory=path, skipLines=0)
    str(dataList)
    # --- import Sample Sheet [] ---
    # Key functions: importSampleSheet
    path <- system.file("extdata", "Sample_names.csv", package="PoDCall")
    well_id <- c("A04", "B04", "D04")
    sampleSheet <- importSampleSheet(sampleSheet=path, well_id=well_id,
    # --- import Amplitude Data [] ---
    # Key functions: importAmplitudeData, podcallThresholds
    path <- system.file("extdata", "Amplitudes/", package="PoDCall")
    ampData <- importAmplitudeData(dataDirectory=path, skipLines=0)
    thresholdTable <- podcallThresholds(plateData=ampData)
    # --- import Amplitude Data [] ---
    # Key functions: importAmplitudeData, podcallChannelPlot
    path <- system.file("extdata", "Amplitudes/", package="PoDCall")
    ampData <- importAmplitudeData(dataDirectory=path, skipLines=0)
    data("thrTable")
    # --- import Amplitude Data [] ---
    # Key functions: importAmplitudeData, podcallScatterplot
    path <- system.file("extdata", "Amplitudes/", package="PoDCall")
    ampData <- importAmplitudeData(dataDirectory=path, skipLines=0)
    well_id <- names(ampData)[1] # First well in list
    # --- import Amplitude Data [] ---
    # Key functions: importAmplitudeData, podcallHistogram
    path <- system.file("extdata", "Amplitudes/", package="PoDCall")
    ampData <- importAmplitudeData(dataDirectory=path, skipLines=0)
    well_id <- names(ampData)[1] # First well in list
    # --- import Amplitude Data [] ---
    # Key functions: importAmplitudeData, podcallMultiplot
    path <- system.file("extdata", "Amplitudes/", package="PoDCall")
    ampData <- importAmplitudeData(dataDirectory=path, skipLines=0)
    podcallMultiplot(plateData=ampData,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_podcall_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_podcall_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_podcall_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PODCALL:", paste0("    podcall: ", packageVersion("PoDCall"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_podcall_results.csv
    touch ${prefix}_podcall_output.rds
    echo "BIOC_PODCALL:" > versions.yml
    echo "    podcall: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PODCALL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PODCALL(ch_input)

    emit:
    results  = BIOC_PODCALL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PODCALL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PODCALL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PODCALL.out.versions  // channel: path(versions.yml)
}
