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
    library(Cardinal)
    library(jsonlite)


    # --- Library [] ---
    # Key functions: exampleImzMLFile, readMSIData, spectraData, spectra, intensity, pixelData, pData, coord
    # library(Cardinal)

    ## ----read-imzML-continuous----------------------------------------------------
    path_continuous <- CardinalIO::exampleImzMLFile("continuous")
    path_continuous
    mse_tiny <- readMSIData(path_continuous)
    mse_tiny

    ## ----read-imzML-processed-----------------------------------------------------
    path_processed <- CardinalIO::exampleImzMLFile("processed")
    set.seed(2020, kind="L'Ecuyer-CMRG")
    s <- simulateSpectra(n=9, npeaks=10, from=500, to=600)

    coord <- expand.grid(x=1:3, y=1:3)
    run <- factor(rep("run0", nrow(coord)))

    fdata <- MassDataFrame(mz=s$mz)
    pdata <- PositionDataFrame(run=run, coord=coord)

    # --- Pdf [] ---
    # Key functions: tempfile, dark, guide, features
    # pdffile <- tempfile(fileext=".pdf")
    # 
    # pdf(file=pdffile, width=9, height=4)
    # image(mse, mz=1003.3)
    # dev.off()

    ## ----style-dark, fig.height=4, fig.width=9------------------------------------
    image(mse, mz=1003.3, style="dark")
    p <- image(mse, mz=1003.3)
    plot(p, smooth="guide")

    ## ----subset-1-----------------------------------------------------------------
    # subset first 5 mass spectra
    msa[1:5]

    ## ----subset-2-----------------------------------------------------------------
    # subset first 10 images and first 5 mass spectra
    mse[1:10, 1:5]
    # get row index corresponding to m/z 1003.3
    features(mse, mz=1003.3)

    # --- Pixels [] ---
    # Key functions: pixels, features, runA1, subsetFeatures, subsetPixels, sliceImage, par, run
    # get column indices corresponding to x = 10, y = 10 in all runs
    pixels(mse, coord=list(x=10, y=10))

    # get column indices corresponding to x <= 3, y <= 3 in "runA1"
    pixels(mse, x <= 3, y <= 3, run == "runA1")

    ## ----subset-3-----------------------------------------------------------------
    fid <- features(mse, 1002 < mz, mz < 1004)
    pid <- pixels(mse, x <= 3, y <= 3, run == "runA1")
    mse[fid, pid]
    # subset features
    subsetFeatures(mse, 1002 < mz, mz < 1004)

    # subset pixels
    subsetPixels(mse, x <= 3, y <= 3)
    # slice image for first mass feature
    a <- sliceImage(mse, 1)
    dim(a)

    ## ----slice-mz-----------------------------------------------------------------

    # --- Matter [] ---
    # Key functions: spectra, spectraData, normalize, smooth, as_facets, tic, gaussian, sgolay
    # spectra are stored as an out-of-memory matrix
    spectra(mse_tiny)
    spectraData(mse_tiny) # 'intensity' array is 'matter_mat' object

    ## -----------------------------------------------------------------------------
    # coerce spectra to an in-memory matrix
    spectra(mse_tiny) <- as.matrix(spectra(mse_tiny))
    spectraData(mse_tiny) # 'intensity' array is 'matrix' object

    ## ----coerce-1-----------------------------------------------------------------
    msa_pre <- normalize(msa, method="tic")

    ## ----smoothSignal-plot, fig.height=7, fig.width=9-----------------------------
    p1 <- smooth(msa, method="gaussian") |>
    	plot(coord=list(x=16, y=16),
    		xlim=c(1150, 1450), linewidth=2)

    p2 <- smooth(msa, method="sgolay") |>
    	plot(coord=list(x=16, y=16),
    		xlim=c(1150, 1450), linewidth=2)

    # --- Reduce Baseline [] ---
    # Key functions: reduceBaseline, simulateImage, locmin, ppm, estimateReferencePeaks, recalibrate, process, peakPick
    msa_pre <- reduceBaseline(msa_pre, method="locmin")

    ## ----unaligned-spectra, fig.height=3, fig.width=9-----------------------------
    set.seed(2020, kind="L'Ecuyer-CMRG")
    mse_drift <- simulateImage(preset=1, npeaks=10,
    	from=500, to=600, sdmz=750, units="ppm")

    plot(mse_drift, i=186:195, xlim=c(535, 570),
    	superpose=TRUE, key=FALSE, linewidth=2)
    peaks_drift <- estimateReferencePeaks(mse_drift)

    mse_nodrift <- recalibrate(mse_drift, ref=peaks_drift,
    	method="locmax", tolerance=1500, units="ppm")
    mse_nodrift <- process(mse_nodrift)

    plot(mse_nodrift, i=186:195, xlim=c(535, 570),
    	superpose=TRUE, key=FALSE, linewidth=2)

    ## ----process-execute----------------------------------------------------------
    msa_peaks <- peakPick(msa_pre, method="filter", SNR=3)

    # --- Peak Align [] ---
    # Key functions: peakAlign, fData, subsetFeatures, summarizeFeatures, peakPick, process, ppm, area
    mse_peaks <- peakAlign(msa_peaks, tolerance=200, units="ppm")
    mse_peaks

    ## ----subsetFeatures-peaks-----------------------------------------------------
    fData(mse_peaks)

    # filter to peaks with frequencies > 0.1
    mse_filt <- subsetFeatures(mse_peaks, freq > 0.1)
    fData(mse_filt)

    mse_peaks3 <- peakProcess(msa_pre, method="diff", SNR=6,
    	sampleSize=0.3, filterFreq=0.02)

    mse_peaks3
    mse_binned <- bin(msa, resolution=1, units="mz")
    mse_binned

    ## ----process-workflow, fig.height=5, fig.width=9------------------------------
    mse_queue <- msa |>
    	normalize() |>

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
