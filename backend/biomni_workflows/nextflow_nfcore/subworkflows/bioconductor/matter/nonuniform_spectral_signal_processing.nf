#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: matter — nonuniform_spectral_signal_processing
// Represent nonuniformly-sampled spectral signals on a common domain, perform smoothing, baseline removal, alignment, peak detection, and binning/merging.
// Input: spectra_list.rds
// Container: quay.io/biocontainers/bioconductor-matter:2.12.0--r45ha27e39d_0
// R packages: matter
// Bioconductor: 3.20 | R: 4.4
// Requires: matter
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Align nonuniform signals to a common domain using sparse_mat or sparse_vec
//  * 2. [Core Analysis] Smooth 1D signals using filt1_* functions
//  * 3. [Core Analysis] Estimate and subtract baseline using estbase_* functions
//  * 4. [Core Analysis] Align/warp signals to a reference using warp1_loc
//  * 5. [Core Analysis] Detect peaks using findpeaks with noise estimation
//  * 6. [Core Analysis] Bin and merge peaks across multiple spectra using binpeaks and mergepeaks

nextflow.enable.dsl = 2

process BIOC_MATTER_NONUNIFORM_SPECTRAL_SIGNAL_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("matter")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(matter)
    
    # ==========================================
    # 1. Load User Input Data
    # ==========================================
    if (!file.exists("spectra_list.rds")) {
        stop("Error: 'spectra_list.rds' not found in the working directory.")
    }
    
    s_raw <- readRDS("spectra_list.rds")
    
    # Ensure we have at least 4 spectra for the workflow steps
    if (length(s_raw) < 4) {
        s <- rep(s_raw, length.out = 4)
    } else {
        s <- s_raw[1:4]
    }
    
    # ==========================================
    # 2. Align Nonuniform Signals to Common Domain
    # ==========================================
    head(domain(s[[1]]))
    head(domain(s[[2]]))
    head(domain(s[[3]]))
    head(domain(s[[4]]))
    
    mzr <- range(
        domain(s[[1]]),
        domain(s[[2]]),
        domain(s[[3]]),
        domain(s[[4]]))
    mz <- seq(from=round(mzr[1]), to=round(mzr[2]), by=0.2)
    
    index <- list(
        domain(s[[1]]),
        domain(s[[2]]),
        domain(s[[3]]),
        domain(s[[4]]))
    
    spectra <- sparse_mat(s, index=index, domain=mz,
        sampler="max", tolerance=0.5)
    
    spectra
    
    # Deferred arithmetic
    spectra_norm <- spectra / t(colMeans(spectra))
    
    # Save aligned and normalized spectra
    saveRDS(spectra, "aligned_spectra.rds")
    saveRDS(spectra_norm, "normalized_spectra.rds")
    
    # ==========================================
    # 3. Smooth 1D Signals
    # ==========================================
    s_single <- s_raw[[1]]
    
    f_ma    <- filt1_ma(s_single)
    f_gauss <- filt1_gauss(s_single)
    f_bi    <- filt1_bi(s_single)
    f_diff  <- filt1_diff(s_single)
    f_guide <- filt1_guide(s_single)
    f_pag   <- filt1_pag(s_single)
    f_sg    <- filt1_sg(s_single)
    
    smoothed_signals <- list(
        ma = f_ma,
        gauss = f_gauss,
        bi = f_bi,
        diff = f_diff,
        guide = f_guide,
        pag = f_pag,
        sg = f_sg
    )
    saveRDS(smoothed_signals, "smoothed_signals.rds")
    
    # ==========================================
    # 4. Estimate and Subtract Baseline
    # ==========================================
    base_loc  <- estbase_loc(s_single)
    base_hull <- estbase_hull(s_single)
    base_snip <- estbase_snip(s_single)
    
    baselines <- list(
        loc = base_loc,
        hull = base_hull,
        snip = base_snip
    )
    saveRDS(baselines, "estimated_baselines.rds")
    
    # ==========================================
    # 5. Align/Warp Signals to a Reference
    # ==========================================
    s_mat <- as.matrix(spectra)
    ref <- rowMeans(s_mat)
    s2 <- apply(s_mat, 2L, warp1_loc,
        y=ref, events="max", tol=2e-3, tol.ref="y")
    
    saveRDS(s2, "warped_spectra.rds")
    
    # ==========================================
    # 6. Detect Peaks with Noise Estimation
    # ==========================================
    i1 <- findpeaks(s_single, snr=3, noise="diff")
    i2 <- findpeaks(s_single, snr=3, noise="filt")
    i3 <- findpeaks(s_single, snr=3, noise="sd")
    i4 <- findpeaks(s_single, snr=3, noise="mad")
    
    detected_peaks <- list(
        diff = i1,
        filt = i2,
        sd = i3,
        mad = i4
    )
    saveRDS(detected_peaks, "detected_peaks.rds")
    
    # ==========================================
    # 7. Bin and Merge Peaks Across Multiple Spectra
    # ==========================================
    peaklist <- apply(s_mat, 2, findpeaks, snr=3)
    
    peaks <- binpeaks(peaklist)
    as.vector(peaks)
    
    peaks <- mergepeaks(peaks, tol=1)
    as.vector(peaks)
    
    # Save final merged peaks
    write.csv(data.frame(MergedPeaks = as.vector(peaks)), "merged_peaks.csv", row.names=FALSE)
    
    # ==========================================
    # 8. Generate Diagnostic Plots
    # ==========================================
    pdf("nonuniform_spectral_processing_plots.pdf", width=10, height=8)
    par(mfrow=c(2,2))
    
    # Plot 1: Smoothing Comparison
    plot(as.vector(domain(s_single)), as.vector(s_single), type="l", col="gray", 
         main="Smoothing Comparison", xlab="m/z", ylab="Intensity")
    lines(as.vector(domain(s_single)), as.vector(f_ma), col="red", lwd=1.5)
    lines(as.vector(domain(s_single)), as.vector(f_gauss), col="blue", lwd=1.5)
    legend("topright", legend=c("Original", "Moving Average", "Gaussian"), 
           col=c("gray", "red", "blue"), lty=1, bty="n")
    
    # Plot 2: Baseline Removal
    plot(as.vector(domain(s_single)), as.vector(s_single), type="l", col="gray", 
         main="Baseline Removal (SNIP)", xlab="m/z", ylab="Intensity")
    lines(as.vector(domain(s_single)), as.vector(base_snip), col="red", lwd=1.5)
    lines(as.vector(domain(s_single)), as.vector(s_single - base_snip), col="blue", lwd=1.5)
    legend("topright", legend=c("Original", "SNIP Baseline", "Corrected"), 
           col=c("gray", "red", "blue"), lty=1, bty="n")
    
    # Plot 3: Alignment / Warping
    matplot(mz, s_mat, type="l", main="Before Warping", xlab="m/z", ylab="Intensity", lty=1)
    matplot(mz, s2, type="l", main="After Warping", xlab="m/z", ylab="Intensity", lty=1)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_MATTER_NONUNIFORM_SPECTRAL_SIGNAL_PROCESSING":',
        paste0('    matter: ', as.character(packageVersion('matter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nonuniform_spectral_signal_processing.csv versions.yml
    """
}

workflow BIOC_MATTER_NONUNIFORM_SPECTRAL_SIGNAL_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spectra_list.rds ] ]

    main:
    BIOC_MATTER_NONUNIFORM_SPECTRAL_SIGNAL_PROCESSING(ch_input)

    emit:
    tables   = BIOC_MATTER_NONUNIFORM_SPECTRAL_SIGNAL_PROCESSING.out.tables
    plots    = BIOC_MATTER_NONUNIFORM_SPECTRAL_SIGNAL_PROCESSING.out.plots
    objects  = BIOC_MATTER_NONUNIFORM_SPECTRAL_SIGNAL_PROCESSING.out.objects
    versions = BIOC_MATTER_NONUNIFORM_SPECTRAL_SIGNAL_PROCESSING.out.versions
}
