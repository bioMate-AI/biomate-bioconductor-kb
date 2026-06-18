#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cosmiq — cosmiq_step_by_step
// Manually preprocess LCMS/GCMS data step-by-step to combine spectra, detect masses, align retention times, and quantify features.
// Input: my.input.files
// Container: quay.io/biocontainers/bioconductor-cosmiq:1.44.0--r45ha27e39d_0
// R packages: cosmiq, xcms
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: image plot

nextflow.enable.dsl = 2

process BIOC_COSMIQ_COSMIQ_STEP_BY_STEP {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cosmiq:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("cosmiq", "xcms")
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
    
    # Load required libraries
    library(cosmiq)
    library(xcms)
    
    # --- Read user input files from the working directory ---
    my.input.files <- list.files(
      path = ".",
      pattern = "\\\\.(CDF|cdf|mzXML|mzxml|mzML|mzml|mzData|mzdata)\$",
      full.names = TRUE,
      recursive = TRUE
    )
    
    if (length(my.input.files) == 0) {
      stop("Error: No raw LCMS/GCMS files (CDF, mzXML, mzML, mzData) found in the working directory.")
    }
    
    # Initialize xcmsSet object
    xs <- new("xcmsSet")
    xs@filepaths <- my.input.files
    
    # Define phenotype data dynamically based on the number of input files
    n_files <- length(my.input.files)
    if (n_files %% 2 == 0) {
      class_labels <- c(rep("KO", n_files / 2), rep("WT", n_files / 2))
    } else {
      class_labels <- rep("Sample", n_files)
    }
    class_df <- as.data.frame(class_labels)
    rownames(class_df) <- basename(my.input.files)
    xs@phenoData <- class_df
    
    # Open PDF device to save plots
    pdf("cosmiq_plots.pdf", width = 10, height = 8)
    
    # --- Combine mass spectra across all scans and runs ---
    x <- combine_spectra(xs=xs, mzbin=0.25, 
    	linear=TRUE, continuum=FALSE)
    
    plot(x\$mz, x\$intensity, type='l',
    	main='combined spectra',
    	xlab='m/Z', ylab='ion intensity')
    
    # --- Detect relevant mass peaks on the master spectrum ---
    xy <- peakdetection(x=x\$mz, y=x\$intensity, 
        scales=1:10, 
        SNR.Th=1.0, 
        SNR.area=20, mintr=0.5)
    
    id.peakcenter<-xy[,4]
    
    filter.mz <- 400 < x\$mz & x\$mz < 450
    plot(x\$mz[filter.mz], x\$intensity[filter.mz], 
        main='Detection of relevant masses',
        type='l',
        xlab='m/Z', 
        ylab='ion intensity')
    
    points(x\$mz[id.peakcenter], 
        x\$intensity[id.peakcenter], 
        col='red', type='h')
    
    # --- Perform retention time alignment using xcms::retcor after ---
    xs@peaks <- matrix(c(rep(1, length(my.input.files) * 6), 
    	1:length(my.input.files)), ncol=7)
    
    colnames(xs@peaks) <- c("mz", "mzmin", "mzmax", "rt", 
    	"rtmin", "rtmax", "sample")
    
    xs <- xcms::retcor(xs, method="obiwarp", profStep=1, 
    	distFunc="cor", center=1)
    
    # --- Generate the extracted ion chromatogram (EIC) matrix ---
    eicmat <- eicmatrix(xs=xs, xy=xy, center=1)
    
    # Process a reduced mz range for better performance and robustness
    mz_indices <- which(475 < xy[,1] & xy[,1] < 485)
    if (length(mz_indices) < 2) {
      # Fallback: use a range of indices around the middle of the detected peaks
      n_peaks <- nrow(xy)
      if (n_peaks >= 2) {
        mid <- floor(n_peaks / 2)
        mz_indices <- max(1, mid - 5):min(n_peaks, mid + 5)
      } else {
        mz_indices <- 1:n_peaks
      }
    }
    eicmat.mz.range <- range(mz_indices)
    
    eicmat.filter <- eicmat[eicmat.mz.range[1]:eicmat.mz.range[2], , drop=FALSE]
    xy.filter <- xy[eicmat.mz.range[1]:eicmat.mz.range[2], , drop=FALSE]
    
    # Determine the new range and plot the mz versus RT map
    rt.range <- range(as.double(colnames(eicmat.filter)))
    mz.range <- range(as.double(row.names(eicmat.filter)))
    
    image(log(t(eicmat.filter))/log(2), 
        main='overlay of samples',
        col=rev(gray(1:20/20)),
        xlab='rt [in seconds]', 
        ylab='m/z', axes=FALSE)
    
    axis(1, seq(0,1, length=6), 
        round(seq(rt.range[1], rt.range[2], length=6)))
    
    axis(2, seq(0,1, length=4), 
        round(seq(mz.range[1], mz.range[2], length=4), 2))
    
    # --- Detect chromatographic peaks in the retention time domain ---
    rxy <- retention_time(xs=xs, 
        RTscales=c(1:10, seq(12,32, by=2)), 
        xy=xy.filter, 
        eicmatrix=eicmat.filter, 
        RTSNR.Th=120, RTSNR.area=20)
    
    if (!is.null(rxy) && nrow(rxy) > 0) {
      rxy.rt <- (rxy[,4] - rt.range[1]) / diff(rt.range)
      rxy.mz <- (rxy[,1] - mz.range[1]) / diff(mz.range)
      points(rxy.rt, rxy.mz, pch="X", lwd=2, col="red")
    }
    
    # Close PDF device
    dev.off()
    
    # --- Quantify features and create the final data matrix ---
    xs <- create_datamatrix(xs=xs, rxy=rxy)
    
    # --- Extract the final peak table ---
    peaktable <- xcms::peakTable(xs)
    
    # Dynamically determine sample columns for sorting
    sample_cols <- 8:(7 + n_files)
    if (length(sample_cols) > 1) {
      idx <- order(rowSums(peaktable[, sample_cols, drop=FALSE]), decreasing=TRUE)
    } else {
      idx <- order(peaktable[, sample_cols], decreasing=TRUE)
    }
    sorted_peaktable <- peaktable[idx, ]
    
    # Save outputs
    write.csv(sorted_peaktable, "cosmiq_peaktable.csv", row.names=FALSE)
    saveRDS(xs, "cosmiq_xcmsSet.rds")

    writeLines(c(
        '"BIOC_COSMIQ_COSMIQ_STEP_BY_STEP":',
        paste0('        cosmiq: ', as.character(packageVersion("cosmiq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosmiq_step_by_step.csv versions.yml
    """
}

workflow BIOC_COSMIQ_COSMIQ_STEP_BY_STEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ my.input.files ] ]

    main:
    BIOC_COSMIQ_COSMIQ_STEP_BY_STEP(ch_input)

    emit:
    tables   = BIOC_COSMIQ_COSMIQ_STEP_BY_STEP.out.tables
    plots    = BIOC_COSMIQ_COSMIQ_STEP_BY_STEP.out.plots
    objects  = BIOC_COSMIQ_COSMIQ_STEP_BY_STEP.out.objects
    versions = BIOC_COSMIQ_COSMIQ_STEP_BY_STEP.out.versions
}
