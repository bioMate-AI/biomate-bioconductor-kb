#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PROcess — mean_spectrum_peaks
// Identify proto-biomarkers using the average spectrum of all raw spectra, baseline-correct it, detect peaks on the mean spectrum, and quantify them in individual
// Input: fs, rtM
// Container: quay.io/biocontainers/bioconductor-process:1.86.0--r45hdfd78af_0
// Requires: PROcess
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute the mean of all raw spectra using aveSpec
//  * 2. [Core Analysis] Subtract baseline from the mean spectrum using bslnoff
//  * 3. [Core Analysis] Detect peaks on the baseline-corrected mean spectrum using isPeak
//  * 4. [Core Analysis] Quantify the identified peaks in individual normalized spectra using getPeaks2

nextflow.enable.dsl = 2

process BIOC_PROCESS_MEAN_SPECTRUM_PEAKS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("PROcess")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required library
    library(PROcess)
    
    # -----------------------------------------------------------------------------
    # 1. INPUT LOADING
    # -----------------------------------------------------------------------------
    # Identify raw mass spectrometry CSV files in the working directory,
    # excluding potential output files and the rtM matrix file.
    all_csvs <- list.files(pattern = "\\\\.csv\$", full.names = TRUE)
    exclude_files <- c("./rtM.csv", "./grandAve.csv", "./grandOff.csv", "./grandpvec.csv", "./grandBmk.csv")
    fs <- all_csvs[!(all_csvs %in% exclude_files)]
    
    if (length(fs) == 0) {
      stop("Error: No raw mass spectrometry CSV files found in the working directory.")
    }
    
    # Load the renormalized spectra matrix (rtM)
    if (file.exists("rtM.rds")) {
      rtM <- readRDS("rtM.rds")
    } else if (file.exists("rtM.csv")) {
      rtM <- as.matrix(read.csv("rtM.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Renormalized spectra matrix file (rtM.rds or rtM.csv) not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. WORKFLOW EXECUTION
    # -----------------------------------------------------------------------------
    # Open PDF device to capture diagnostic plots from bslnoff and isPeak
    pdf("mean_spectrum_plots.pdf", width = 10, height = 8)
    
    # Step 1: Compute the mean of all raw spectra
    grandAve <- aveSpec(fs)
    mzs <- grandAve[,1]
    
    # Step 2: Subtract baseline from the mean spectrum
    grandOff <- bslnoff(grandAve[mzs>0,], method="loess",
            plot=T, bw=0.1)
    
    # Step 3: Detect peaks on the baseline-corrected mean spectrum
    grandPkg <- isPeak(grandOff[grandOff[,1]>1500,], zerothrsh=1,
    plot=T, ratio=0.1)
    grandpvec <- round(grandPkg[grandPkg\$peak, "mz"])
    print(as.vector(grandpvec))
    
    # Close the PDF device
    dev.off()
    
    # Step 4: Quantify the identified peaks in individual normalized spectra
    grandBmk <- getPeaks2(rtM, grandpvec)
    
    # -----------------------------------------------------------------------------
    # 3. OUTPUT WRITING
    # -----------------------------------------------------------------------------
    # Save the average spectrum
    write.csv(grandAve, "grandAve.csv", row.names = FALSE)
    
    # Save the baseline-corrected average spectrum
    write.csv(grandOff, "grandOff.csv", row.names = FALSE)
    
    # Save the identified peak m/z vector
    write.csv(data.frame(peak_mz = grandpvec), "grandpvec.csv", row.names = FALSE)
    
    # Save the quantified peak intensities (proto-biomarkers)
    write.csv(grandBmk, "grandBmk.csv", row.names = TRUE)
    saveRDS(grandBmk, "grandBmk.rds")
    
    cat("Workflow completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_PROCESS_MEAN_SPECTRUM_PEAKS":',
        paste0('    PROcess: ', as.character(packageVersion('PROcess')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mean_spectrum_peaks.csv versions.yml
    """
}

workflow BIOC_PROCESS_MEAN_SPECTRUM_PEAKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fs, rtM ] ]

    main:
    BIOC_PROCESS_MEAN_SPECTRUM_PEAKS(ch_input)

    emit:
    tables   = BIOC_PROCESS_MEAN_SPECTRUM_PEAKS.out.tables
    plots    = BIOC_PROCESS_MEAN_SPECTRUM_PEAKS.out.plots
    objects  = BIOC_PROCESS_MEAN_SPECTRUM_PEAKS.out.objects
    versions = BIOC_PROCESS_MEAN_SPECTRUM_PEAKS.out.versions
}
