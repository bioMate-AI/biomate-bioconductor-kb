#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gcapc — gc_corrected_peak_calling_and_refining
// Perform GC-bias-corrected peak calling and refine peak significance from a ChIP-seq BAM file.
// Input: chipseq.bam
// Container: quay.io/biocontainers/bioconductor-gcapc:1.34.0--r45hdfd78af_0
// R packages: gcapc
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GCAPC_GC_CORRECTED_PEAK_CALLING_AND_REFINING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gcapc:1.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("gcapc")
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
    library(gcapc)
    
    # Define input file (must exist in the working directory)
    bam <- "chipseq.bam"
    
    if (!file.exists(bam)) {
      stop("Error: Input file 'chipseq.bam' not found in the working directory.")
    }
    
    # --- Read 5' end coverage from BAM ---
    message("Stage 1: Reading 5' end coverage...")
    cov <- read5endCoverage(bam)
    saveRDS(cov, "coverage.rds")
    
    # --- Estimate binding width and peak window half size ---
    message("Stage 2: Estimating binding width...")
    bdw <- bindWidth(cov, range=c(50L,300L), step=10L)
    saveRDS(bdw, "binding_width.rds")
    
    # Open PDF device to capture all generated plots
    pdf("gcapc_analysis_plots.pdf", width=10, height=5)
    
    # --- Estimate GC effects using mixture models ---
    message("Stage 3: Estimating GC effects...")
    layout(matrix(1:2,1,2))
    gcb <- gcEffects(cov, bdw, sampling=c(0.25,1), plot=TRUE, model='poisson')
    saveRDS(gcb, "gc_effects.rds")
    
    # --- Call peaks and evaluate significance ---
    message("Stage 4: Calling peaks and evaluating significance...")
    layout(matrix(1:2,1,2))
    peaks <- gcapcPeaks(cov, gcb, bdw, plot=TRUE, permute=100L)
    peaks <- gcapcPeaks(cov, gcb, bdw, plot=TRUE, permute=50L)
    saveRDS(peaks, "peaks.rds")
    write.csv(as.data.frame(peaks), "peaks.csv", row.names=FALSE)
    
    # --- Refine peak significance ---
    message("Stage 5: Refining peak significance...")
    newpeaks <- refinePeaks(cov, gcb, bdw, peaks=peaks, permute=50L)
    saveRDS(newpeaks, "refined_peaks.rds")
    write.csv(as.data.frame(newpeaks), "refined_peaks.csv", row.names=FALSE)
    
    # Plot comparison of old vs new scores
    plot(newpeaks\$es,newpeaks\$newes,xlab='old score',ylab='new score')
    
    # Close PDF device
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to current directory.")

    writeLines(c(
        '"BIOC_GCAPC_GC_CORRECTED_PEAK_CALLING_AND_REFINING":',
        paste0('        gcapc: ', as.character(packageVersion("gcapc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gc_corrected_peak_calling_and_refining.csv versions.yml
    """
}

workflow BIOC_GCAPC_GC_CORRECTED_PEAK_CALLING_AND_REFINING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chipseq.bam ] ]

    main:
    BIOC_GCAPC_GC_CORRECTED_PEAK_CALLING_AND_REFINING(ch_input)

    emit:
    tables   = BIOC_GCAPC_GC_CORRECTED_PEAK_CALLING_AND_REFINING.out.tables
    plots    = BIOC_GCAPC_GC_CORRECTED_PEAK_CALLING_AND_REFINING.out.plots
    objects  = BIOC_GCAPC_GC_CORRECTED_PEAK_CALLING_AND_REFINING.out.objects
    versions = BIOC_GCAPC_GC_CORRECTED_PEAK_CALLING_AND_REFINING.out.versions
}
