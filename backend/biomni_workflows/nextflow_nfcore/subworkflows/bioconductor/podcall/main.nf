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

    # --- Data Import [Importing ddPCR amplitude data and sample sheets] ---
    # Key functions: importAmplitudeData, importSampleSheet
    path_amp <- system.file("extdata", "Amplitudes/", package = "PoDCall")
    path_ss <- system.file("extdata", "Sample_names.csv", package = "PoDCall")
    well_id <- c("A04", "B04", "D04")
    ampData <- importAmplitudeData(dataDirectory = path_amp, skipLines = 0)
    sampleSheet <- importSampleSheet(
        sampleSheet = path_ss,
        well_id = well_id,
        software = "QuantaSoft"
    )

    # --- Threshold Estimation [Calculating thresholds and concentrations] ---
    # Key functions: podcallThresholds, podcallDdpcr
    path_amp <- system.file("extdata", "Amplitudes/", package = "PoDCall")
    ampData <- importAmplitudeData(dataDirectory = path_amp, skipLines = 0)
    thresholdTable <- podcallThresholds(plateData = ampData)

    # --- Single Well Visualization [Plotting channel amplitudes and scatterplots] ---
    # Key functions: podcallChannelPlot, podcallScatterplot
    path_amp <- system.file("extdata", "Amplitudes/", package = "PoDCall")
    ampData <- importAmplitudeData(dataDirectory = path_amp, skipLines = 0)
    data("thrTable", package = "PoDCall")
    well_id <- names(ampData)[1]
    podcallChannelPlot(
        channelData = ampData[[well_id]][, 1],
        thr = thrTable[well_id, "thr_target"],
        channel = 1,
        plotId = paste0(well_id, ", Ch1")
    )
    podcallScatterplot(
        channelData = ampData[[well_id]][, 1],
        thr = thrTable[well_id, "thr_target"],
        channel = 1,
        plotId = paste0(well_id, ", Ch1")
    )

    # --- Distribution and Multi-well Analysis [Plotting histograms and multi-well comparisons] ---
    # Key functions: podcallHistogram, podcallMultiplot
    path_amp <- system.file("extdata", "Amplitudes/", package = "PoDCall")
    ampData <- importAmplitudeData(dataDirectory = path_amp, skipLines = 0)
    data("thrTable", package = "PoDCall")
    well_id <- names(ampData)[1]
    podcallHistogram(
        channelData = ampData[[well_id]][, 1],
        thr = thrTable[well_id, "thr_target"],
        channel = 1,
        plotId = paste0(well_id, ", Ch1")
    )
    podcallMultiplot(
        plateData = ampData,
        thresholds = thrTable[names(ampData), ],
        channel = "target",
        colCh = 1
    )


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
