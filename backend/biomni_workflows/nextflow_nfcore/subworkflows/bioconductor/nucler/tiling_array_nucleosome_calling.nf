#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nucler — tiling_array_nucleosome_calling
// Process Tiling Array fluorescence intensities to call and score nucleosome positions.
// Input: tiling_data.RData
// Container: quay.io/biocontainers/bioconductor-nucler:2.42.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NUCLER_TILING_ARRAY_NUCLEOSOME_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-nucler:2.42.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "GenomicRanges", "IRanges", "nucleR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(nucleR)
    library(IRanges)
    library(GenomicRanges)
    
    # Helper to safely load Biobase if dealing with ExpressionSet
    if (requireNamespace("Biobase", quietly = TRUE)) {
        library(Biobase)
    }
    
    # ==========================================
    # 1. Load User Input
    # ==========================================
    input_file <- "tiling_data.RData"
    if (!file.exists(input_file)) {
        stop(paste("Required input file missing:", input_file))
    }
    
    # Load the RData file into a temporary environment to avoid namespace pollution
    env <- new.env()
    load(input_file, envir = env)
    loaded_objs <- ls(env)
    
    if (length(loaded_objs) == 0) {
        stop("The loaded RData file is empty.")
    }
    
    # Extract the primary data object
    raw_data <- env[[loaded_objs[1]]]
    
    # ==========================================
    # Stage 1: Process tiling array data to 1bp resolution
    # ==========================================
    if (inherits(raw_data, "ExpressionSet")) {
        # If the input is an ExpressionSet, we must process it using processTilingArray
        # Extract sample name and define a default chromosome pattern
        exprName <- Biobase::sampleNames(raw_data)[1]
        chrPattern <- "chr.*"
        
        message("Processing ExpressionSet using processTilingArray...")
        nucleosome_tiling <- processTilingArray(raw_data, exprName, chrPattern, inferLen=50)
    } else if (is.numeric(raw_data)) {
        # If it is already a preprocessed numeric vector of intensities
        message("Input is a numeric vector. Using directly as preprocessed tiling data.")
        nucleosome_tiling <- raw_data
    } else {
        stop("Input data must be either an ExpressionSet or a numeric vector of intensities.")
    }
    
    # ==========================================
    # Stage 2: Smooth signal using filterFFT
    # ==========================================
    # Save the power spectrum plot to a PDF
    pdf("power_spectrum.pdf")
    fft_ta <- filterFFT(nucleosome_tiling, pcKeepComp=0.01, showPowerSpec=TRUE)
    dev.off()
    
    # Perform the documented filtering steps
    tiling_raw <- nucleosome_tiling
    tiling_fft <- filterFFT(tiling_raw, pcKeepComp=0.01)
    
    # Save the smoothed signal
    saveRDS(tiling_fft, "tiling_fft.rds")
    
    # ==========================================
    # Stage 3: Detect peaks using peakDetection
    # ==========================================
    # Detect peaks without scoring
    peaks_raw <- peakDetection(tiling_fft, threshold="25%", score=FALSE)
    
    # Detect peaks with scoring and width to account for fuzziness
    peaks_scored <- peakDetection(tiling_fft, threshold="25%", score=TRUE, width=140)
    
    # Save peak detection plots
    pdf("peaks_plot.pdf")
    plotPeaks(peaks_scored, tiling_fft, threshold="25%", ylab="intensity")
    dev.off()
    
    # Save the results
    saveRDS(peaks_scored, "detected_peaks.rds")
    
    # Export peaks to a CSV table
    if (inherits(peaks_scored, "GRanges")) {
        peaks_df <- as.data.frame(peaks_scored)
        write.csv(peaks_df, "detected_peaks.csv", row.names=FALSE)
    } else {
        write.csv(data.frame(peak_position = peaks_raw), "detected_peaks.csv", row.names=FALSE)
    }
    
    message("Pipeline completed successfully. Outputs saved: power_spectrum.pdf, tiling_fft.rds, peaks_plot.pdf, detected_peaks.rds, detected_peaks.csv")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NUCLER_TILING_ARRAY_NUCLEOSOME_CALLING":
        nucler: \$(Rscript -e 'cat(as.character(packageVersion("nucler")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tiling_array_nucleosome_calling.csv versions.yml
    """
}

workflow BIOC_NUCLER_TILING_ARRAY_NUCLEOSOME_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tiling_data.RData ] ]

    main:
    BIOC_NUCLER_TILING_ARRAY_NUCLEOSOME_CALLING(ch_input)

    emit:
    tables   = BIOC_NUCLER_TILING_ARRAY_NUCLEOSOME_CALLING.out.tables
    plots    = BIOC_NUCLER_TILING_ARRAY_NUCLEOSOME_CALLING.out.plots
    objects  = BIOC_NUCLER_TILING_ARRAY_NUCLEOSOME_CALLING.out.objects
    versions = BIOC_NUCLER_TILING_ARRAY_NUCLEOSOME_CALLING.out.versions
}
