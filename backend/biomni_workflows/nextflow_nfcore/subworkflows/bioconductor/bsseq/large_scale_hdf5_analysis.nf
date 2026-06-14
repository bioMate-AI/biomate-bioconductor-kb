#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bsseq — large_scale_hdf5_analysis
// Process large-scale WGBS datasets using HDF5-backed objects to bound memory consumption.
// Input: bismark_files.cov
// Container: quay.io/biocontainers/bioconductor-bsseq:1.46.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, GenomicRanges, HDF5Array, bsseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read Bismark files directly into an HDF5-backed BSseq object
//  * 2. [Core Analysis] Alternatively, convert an existing in-memory BSseq object to HDF5
//  * 3. [Input & Preparation] Load the HDF5-backed object
//  * 4. [Core Analysis] Run parallelized smoothing with bounded memory

nextflow.enable.dsl = 2

process BIOC_BSSEQ_LARGE_SCALE_HDF5_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("bsseq", "HDF5Array", "BiocParallel", "GenomicRanges")
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
    library(bsseq)
    library(HDF5Array)
    library(BiocParallel)
    library(GenomicRanges)
    
    # Define the input file as specified by the user
    bismarkfiles <- "bismark_files.cov"
    
    # Check if the input file exists
    if (!file.exists(bismarkfiles)) {
      stop(paste("Required input file missing:", bismarkfiles))
    }
    
    # Clean up any pre-existing directories to avoid saveHDF5SummarizedExperiment errors
    if (dir.exists("./BSseqName.h5")) {
      unlink("./BSseqName.h5", recursive = TRUE)
    }
    if (dir.exists("./BSseq_smoothed.h5")) {
      unlink("./BSseq_smoothed.h5", recursive = TRUE)
    }
    
    # 1. Read Bismark files directly into an HDF5-backed BSseq object
    BSseq <- read.bismark(bismarkfiles, BACKEND = "HDF5Array", BPPARAM = MulticoreParam(workers = 10))
    
    # 2. Convert/Save the BSseq object to HDF5
    saveHDF5SummarizedExperiment(BSseq, dir = "./BSseqName.h5")
    
    # 3. Load the HDF5-backed object
    BSseq <- loadHDF5SummarizedExperiment(dir = "./BSseqName.h5")
    
    # 4. Run parallelized smoothing with bounded memory
    BSseq <- BSmooth(BSseq, BPPARAM = MulticoreParam(workers = 10))
    
    # Save the final smoothed HDF5-backed object
    saveHDF5SummarizedExperiment(BSseq, dir = "./BSseq_smoothed.h5")
    
    # Write meaningful results to output files
    # 1. CSV Summary Table
    summary_df <- data.frame(
      Metric = c("Number_of_Loci", "Number_of_Samples", "Sample_Names"),
      Value = c(
        nrow(BSseq),
        ncol(BSseq),
        paste(sampleNames(BSseq), collapse = ", ")
      )
    )
    write.csv(summary_df, file = "smoothed_summary.csv", row.names = FALSE)
    
    # 2. PDF Plot of a region
    pdf("methylation_plot.pdf", width = 10, height = 5)
    if (nrow(BSseq) > 0) {
      # Define a region around the first locus to plot
      first_start <- start(BSseq)[1]
      first_chr <- as.character(seqnames(BSseq)[1])
      plot_region <- GRanges(
        seqnames = first_chr,
        ranges = IRanges(start = max(1, first_start - 5000), end = first_start + 5000)
      )
      
      # Attempt to plot the region
      tryCatch({
        plotRegion(BSseq, plot_region)
      }, error = function(e) {
        warning("Could not plot region: ", e\$message)
      })
    } else {
      plot.new()
      text(0.5, 0.5, "No loci available to plot")
    }
    dev.off()

    writeLines(c(
        '"BIOC_BSSEQ_LARGE_SCALE_HDF5_ANALYSIS":',
        paste0('    bsseq: ', as.character(packageVersion('bsseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_scale_hdf5_analysis.csv versions.yml
    """
}

workflow BIOC_BSSEQ_LARGE_SCALE_HDF5_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bismark_files.cov ] ]

    main:
    BIOC_BSSEQ_LARGE_SCALE_HDF5_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BSSEQ_LARGE_SCALE_HDF5_ANALYSIS.out.tables
    plots    = BIOC_BSSEQ_LARGE_SCALE_HDF5_ANALYSIS.out.plots
    objects  = BIOC_BSSEQ_LARGE_SCALE_HDF5_ANALYSIS.out.objects
    versions = BIOC_BSSEQ_LARGE_SCALE_HDF5_ANALYSIS.out.versions
}
