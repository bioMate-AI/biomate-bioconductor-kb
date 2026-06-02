#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msPurity
// msPurity R package was developed to: 1) Assess the spectral quality of fragmentation spectra by eval
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msPurity/inst/doc/msPurity-lcmsms-data-processing-and-spectral-matching-vignette.R
// Upstream  : MSnbase, magrittr, xcms
// Downstream: none
//
// Install: BiocManager::install("msPurity")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSPURITY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mspurity"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mspurity:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mspurity:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mspurity_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mspurity_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mspurity_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(msPurity)
    library(jsonlite)


    # --- Results='hide' [] ---
    # Key functions: list.files, xcmsSet, group, extdata, lcms, mzML, msPurityData
    library(msPurity)
    library(xcms)
    mzMLpths <- list.files(system.file("extdata", "lcms", "mzML", package="msPurityData"), full.names = TRUE)

    #read in the data
    xset = xcms::xcmsSet(mzMLpths, method = 'centWave', mslevel=1, snthresh = 3, noise = 100, ppm = 10, peakwidth = c(3, 30))

    #for this example we will subset the data to focus on retention time range 30-90 seconds and scan range 100-200 m/z
    xset@peaks = xset@peaks[xset@peaks[,4] >= 30 & xset@peaks[,4] <= 90,] #retention time filter
    xset@peaks = xset@peaks[xset@peaks[,1] >= 100 & xset@peaks[,1] <= 200,] #m/z filter

    # --- Results='hide' [] ---
    # Key functions: list.files, readMSData, filterRt, filterMz, CentWaveParam, findChromPeaks, samples, PeakDensityParam
    library(msPurity)
    library(magrittr)
    library(xcms)
    library(MSnbase)
    mzMLpths <- list.files(system.file("extdata", "lcms", "mzML", package="msPurityData"), full.names = TRUE)

    #read in data and subset to use data between 30 and 90 seconds and 100 and 200 m/z
    msdata = readMSData(mzMLpths, mode = 'onDisk', msLevel. = 1)
    rtr = c(30, 90)
    mzr = c(100, 200)

    # --- Results='hide' [] ---
    # Key functions: purityA, frag4feature
    pa  <- purityA(mzMLpths)
    pa <- frag4feature(pa = pa, xcmsObj = xcmsObj)

    # --- Results='hide' [] ---
    # Key functions: filterFragSpectra
    pa <- filterFragSpectra(pa = pa)

    # --- Results='hide' [] ---
    # Key functions: averageIntraFragSpectra, averageInterFragSpectra
    pa <- averageIntraFragSpectra(pa = pa) # use parameters specific to intra spectra 
    pa <- averageInterFragSpectra(pa = pa) # use parameters specific to inter spectra

    # --- Results='hide' [] ---
    # Key functions: averageAllFragSpectra
    pa <- averageAllFragSpectra(pa = pa)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mspurity_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mspurity_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mspurity_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSPURITY:", paste0("    mspurity: ", packageVersion("msPurity"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mspurity_results.csv
    touch ${prefix}_mspurity_output.rds
    echo "BIOC_MSPURITY:" > versions.yml
    echo "    mspurity: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSPURITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSPURITY(ch_input)

    emit:
    results  = BIOC_MSPURITY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSPURITY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSPURITY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSPURITY.out.versions  // channel: path(versions.yml)
}
