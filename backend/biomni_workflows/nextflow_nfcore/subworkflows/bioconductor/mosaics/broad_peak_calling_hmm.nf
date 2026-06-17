#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosaics — broad_peak_calling_hmm
// Identify broad peaks (e.g., histone modifications) using ChIP and matched control samples with HMM and post-processing.
// Input: wgEncodeBroadHistoneGm12878H3k4me3StdAlnRep1_chr22_sorted.bam, wgEncodeBroadHistoneGm12878ControlStdAlnRep1_chr22_sorted.bam
// Container: quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0
// R packages: mosaics
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSAICS_BROAD_PEAK_CALLING_HMM {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0"

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
    .bm_deps <- c("mosaics")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required library
    library(mosaics)
    
    # Define input files in the working directory
    chip_file <- "wgEncodeBroadHistoneGm12878H3k4me3StdAlnRep1_chr22_sorted.bam"
    control_file <- "wgEncodeBroadHistoneGm12878ControlStdAlnRep1_chr22_sorted.bam"
    
    # Verify that the required input files exist in the working directory
    if (!file.exists(chip_file)) {
      stop(paste("Required ChIP input file missing from working directory:", chip_file))
    }
    if (!file.exists(control_file)) {
      stop(paste("Required Control input file missing from working directory:", control_file))
    }
    
    # ==========================================
    # --- Construct bin-level files ---
    # ==========================================
    message("Constructing bin-level files...")
    constructBins( infile=chip_file, 
        fileFormat="bam", outfileLoc="./", 
        byChr=FALSE, useChrfile=FALSE, chrfile=NULL, excludeChr=NULL, 
        PET=FALSE, fragLen=200, binSize=200, capping=0 )
    
    constructBins( infile=control_file, 
        fileFormat="bam", outfileLoc="./", 
        byChr=FALSE, useChrfile=FALSE, chrfile=NULL, excludeChr=NULL, 
        PET=FALSE, fragLen=200, binSize=200, capping=0 )
    
    # ==========================================
    # --- Read bin-level data ---
    # ==========================================
    message("Reading bin-level data...")
    fileName <- c(
        "wgEncodeBroadHistoneGm12878H3k4me3StdAlnRep1_chr22_sorted.bam_fragL200_bin200.txt",
        "wgEncodeBroadHistoneGm12878ControlStdAlnRep1_chr22_sorted.bam_fragL200_bin200.txt")
    
    binHM <- readBins( type=c("chip","input"), fileName=fileName)
    
    # Save exploratory plots of bin-level data
    pdf("mosaics_exploratory_plots.pdf", width=8, height=6)
    plot(binHM)
    plot(binHM, plotType="input")
    dev.off()
    
    # ==========================================
    # --- Fit initial MOSAiCS model ---
    # ==========================================
    message("Fitting initial MOSAiCS model...")
    fitHM <- mosaicsFit( binHM, analysisType="IO", bgEst="rMOM" )
    
    # Save Goodness of Fit plot for initial model
    pdf("mosaics_fit_gof.pdf", width=8, height=6)
    plot(fitHM)
    dev.off()
    
    # ==========================================
    # --- Fit MOSAiCS-HMM model ---
    # ==========================================
    message("Fitting MOSAiCS-HMM model...")
    hmmHM <- mosaicsFitHMM( fitHM, signalModel = "2S", 
    	init="mosaics", init.FDR = 0.05, parallel=FALSE, nCore=8 )
    
    # Save Goodness of Fit plot for HMM model
    pdf("mosaics_hmm_fit_gof.pdf", width=8, height=6)
    plot(hmmHM)
    dev.off()
    
    # ==========================================
    # --- Call peaks using HMM ---
    # ==========================================
    message("Calling peaks using HMM...")
    peakHM <- mosaicsPeakHMM( hmmHM, FDR = 0.05, decoding="posterior",
      thres=10, parallel=FALSE, nCore=8 )
    
    # ==========================================
    # --- Extract read-level data ---
    # ==========================================
    message("Extracting read-level data...")
    peakHM <- extractReads( peakHM,
      chipFile=chip_file,
      chipFileFormat="bam", chipPET=FALSE, chipFragLen=200,
      controlFile=control_file, 
      controlFileFormat="bam", controlPET=FALSE, controlFragLen=200, parallel=FALSE, nCore=8 )
    
    # ==========================================
    # --- Find peak summits ---
    # ==========================================
    message("Finding peak summits...")
    peakHM <- findSummit( peakHM, parallel=FALSE, nCore=8 )
    
    # ==========================================
    # --- Adjust peak boundaries ---
    # ==========================================
    message("Adjusting peak boundaries...")
    peakHM <- adjustBoundary( peakHM, parallel=FALSE, nCore=8 )
    
    # ==========================================
    # --- Filter peaks ---
    # ==========================================
    message("Filtering peaks...")
    peakHM <- filterPeak( peakHM, parallel=FALSE, nCore=8 )
    
    # ==========================================
    # Export Results and Outputs
    # ==========================================
    message("Exporting results...")
    
    # Save the final peakHM object as an RDS file
    saveRDS(peakHM, file="mosaics_peakHM_final.rds")
    
    # Export peak lists in multiple standard formats
    export( peakHM, type="txt", filename="mosaics_peaks.txt" )
    export( peakHM, type="bed", filename="mosaics_peaks.bed" )
    export( peakHM, type="gff", filename="mosaics_peaks.gff" )
    export( peakHM, type="narrowPeak", filename="mosaics_peaks.narrowPeak" )
    export( peakHM, type="broadPeak", filename="mosaics_peaks.broadPeak" )
    
    # Write the peak table to a CSV file
    peak_table <- print(peakHM)
    write.csv(peak_table, file="mosaics_peaks_summary.csv", row.names=FALSE)
    
    # Generate ChIP profile plots of peak regions
    tryCatch({
      plot( peakHM, filename="./mosaics_peak_profiles.pdf" )
    }, error = function(e) {
      warning("Could not generate all peak profile plots: ", e\$message)
    })
    
    # Generate a single peak profile plot for a representative peak if peaks exist
    if (nrow(peak_table) >= 1) {
      tryCatch({
        pdf("mosaics_representative_peak_profile.pdf", width=8, height=6)
        plot( peakHM, peakNum=1 )
        dev.off()
      }, error = function(e) {
        warning("Could not generate representative peak profile plot: ", e\$message)
      })
    }
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MOSAICS_BROAD_PEAK_CALLING_HMM":',
        paste0('        mosaics: ', as.character(packageVersion("mosaics")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_broad_peak_calling_hmm.csv versions.yml
    """
}

workflow BIOC_MOSAICS_BROAD_PEAK_CALLING_HMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ wgEncodeBroadHistoneGm12878H3k4me3StdAlnRep1_chr22_sorted.bam, wgEncodeBroadHistoneGm12878ControlStdAlnRep1_chr22_sorted.bam ] ]

    main:
    BIOC_MOSAICS_BROAD_PEAK_CALLING_HMM(ch_input)

    emit:
    tables   = BIOC_MOSAICS_BROAD_PEAK_CALLING_HMM.out.tables
    plots    = BIOC_MOSAICS_BROAD_PEAK_CALLING_HMM.out.plots
    objects  = BIOC_MOSAICS_BROAD_PEAK_CALLING_HMM.out.objects
    versions = BIOC_MOSAICS_BROAD_PEAK_CALLING_HMM.out.versions
}
