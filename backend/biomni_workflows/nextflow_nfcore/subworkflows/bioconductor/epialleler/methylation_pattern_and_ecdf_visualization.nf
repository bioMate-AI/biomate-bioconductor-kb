#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleleR — methylation_pattern_and_ecdf_visualization
// Extract and visualize individual DNA methylation patterns and per-read beta value cumulative distributions (eCDFs) for genomic regions of interest.
// Input: amplicon010meth.bam, amplicon.bed
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// R packages: GenomicRanges, epialleleR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, epialleleR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract methylation patterns for a specific genomic range
//  * 2. [Visualization & Output] Plot the extracted patterns
//  * 3. [Visualization & Output] Compute and plot empirical cumulative distribution functions (eCDFs) for within- and out-of-context beta values

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_METHYLATION_PATTERN_AND_ECDF_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "epialleleR")
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
    library(methods)
    library(GenomicRanges)
    library(epialleleR)
    
    # Define input files from the working directory
    bam_file <- "amplicon010meth.bam"
    bed_file <- "amplicon.bed"
    
    # Verify input files exist
    if (!file.exists(bam_file)) {
      stop(paste("Required BAM file missing:", bam_file))
    }
    if (!file.exists(bed_file)) {
      stop(paste("Required BED file missing:", bed_file))
    }
    
    # ==========================================
    # Stage 1: Extract methylation patterns
    # ==========================================
    message("Extracting methylation patterns...")
    patterns <- extractPatterns(
      bam=bam_file,
      bed=as("chr17:43125200-43125600","GRanges")
    )
    
    # Print number of patterns
    num_patterns <- nrow(patterns)
    cat("Number of patterns extracted:", num_patterns, "\n")
    
    # Save extracted patterns to CSV
    write.csv(patterns, "extracted_patterns.csv", row.names=FALSE)
    
    
    # ==========================================
    # Stage 2: Plot the extracted patterns
    # ==========================================
    message("Plotting extracted patterns...")
    pdf("methylation_patterns_default.pdf", width=10, height=6)
    plotPatterns(patterns)
    dev.off()
    
    # Extract and plot patterns with discrete scale (adapted to use available BAM and GRanges)
    capture.patterns <- extractPatterns(
      bam=bam_file,
      bed=as("chr17:43125200-43125600", "GRanges"),
      verbose=FALSE
    )
    
    # Save adapted capture patterns to CSV
    write.csv(capture.patterns, "capture_patterns_adapted.csv", row.names=FALSE)
    
    pdf("methylation_patterns_discrete.pdf", width=10, height=6)
    plotPatterns(capture.patterns, npatterns.per.bin=Inf,
                 genomic.scale="discrete", context.size=1)
    dev.off()
    
    
    # ==========================================
    # Stage 3: Compute and plot eCDFs
    # ==========================================
    message("Computing empirical cumulative distribution functions (eCDFs)...")
    amplicon.ecdfs <- generateBedEcdf(
      bam=bam_file,
      bed=bed_file,
      bed.rows=NULL
    )
    
    # Save eCDF object to RDS
    saveRDS(amplicon.ecdfs, "amplicon_ecdfs.rds")
    
    # Plot eCDFs for within- and out-of-context beta values
    message("Plotting eCDFs...")
    pdf("ecdf_plots.pdf", width=12, height=4)
    par(mfrow=c(1, length(amplicon.ecdfs)))
    
    for (x in 1:length(amplicon.ecdfs)) {
      main <- if (is.na(names(amplicon.ecdfs[x]))) "unmatched" else names(amplicon.ecdfs[x])
      
      # Plot within-context (red)
      plot(amplicon.ecdfs[[x]]\$context, col="red", verticals=TRUE, do.points=FALSE,
           xlim=c(0, 1), xlab="per-read beta value", ylab="cumulative density", main=main)
      
      # Add out-of-context (blue)
      plot(amplicon.ecdfs[[x]]\$out.of.context, add=TRUE, col="blue", verticals=TRUE, do.points=FALSE)
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_EPIALLELER_METHYLATION_PATTERN_AND_ECDF_VISUALIZATION":',
        paste0('    epialleleR: ', as.character(packageVersion('epialleleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_pattern_and_ecdf_visualization.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_METHYLATION_PATTERN_AND_ECDF_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ amplicon010meth.bam, amplicon.bed ] ]

    main:
    BIOC_EPIALLELER_METHYLATION_PATTERN_AND_ECDF_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_METHYLATION_PATTERN_AND_ECDF_VISUALIZATION.out.tables
    plots    = BIOC_EPIALLELER_METHYLATION_PATTERN_AND_ECDF_VISUALIZATION.out.plots
    objects  = BIOC_EPIALLELER_METHYLATION_PATTERN_AND_ECDF_VISUALIZATION.out.objects
    versions = BIOC_EPIALLELER_METHYLATION_PATTERN_AND_ECDF_VISUALIZATION.out.versions
}
