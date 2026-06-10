#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SICtools — indel_difference_detection
// Detect short insertion and deletion (Indel) differences between two closely related BAM files across a genomic region of interest.
// Input: bam1.bam, bam2.bam, ref.fasta
// Container: quay.io/biocontainers/bioconductor-sictools:1.30.0--r43h54b6a8d_0
// R packages: Rsamtools, SICtools
// Bioconductor: 3.20 | R: 4.4
// Requires: Rsamtools, SICtools
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define input file paths
//  * 2. [Core Analysis] Run Indel comparison using indelDiff
//  * 3. [Core Analysis] Sort results by p-value and d-value to identify candidate variants

nextflow.enable.dsl = 2

process BIOC_SICTOOLS_INDEL_DIFFERENCE_DETECTION {
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
    .bm_deps <- c("Rsamtools", "SICtools")
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
    library(SICtools)
    library(Rsamtools)
    
    # 1. Define input file paths from the working directory
    bam1 <- "bam1.bam"
    bam2 <- "bam2.bam"
    refFsa <- "ref.fasta"
    
    # Robustness: Ensure BAM and FASTA index files exist, create them if missing
    if (!file.exists(paste0(bam1, ".bai")) && !file.exists(sub("\\\\.bam\$", ".bai", bam1))) {
      message("Indexing bam1.bam...")
      tryCatch(indexBam(bam1), error = function(e) message("Warning: Could not index bam1.bam: ", e\$message))
    }
    if (!file.exists(paste0(bam2, ".bai")) && !file.exists(sub("\\\\.bam\$", ".bai", bam2))) {
      message("Indexing bam2.bam...")
      tryCatch(indexBam(bam2), error = function(e) message("Warning: Could not index bam2.bam: ", e\$message))
    }
    if (!file.exists(paste0(refFsa, ".fai"))) {
      message("Indexing ref.fasta...")
      tryCatch(indexFa(refFsa), error = function(e) message("Warning: Could not index ref.fasta: ", e\$message))
    }
    
    # Define default genomic region coordinates from the documented vignette
    regChr <- 'chr07'
    regStart <- 828514
    regEnd <- 828914
    
    # Dynamically adjust coordinates to match the user's input BAM files if necessary
    tryCatch({
      hdr <- scanBamHeader(bam1)
      targets <- hdr[[1]]\$targets
      if (length(targets) > 0) {
        if ("chr07" %in% names(targets)) {
          regChr <- "chr07"
          if (targets["chr07"] < regEnd) {
            regStart <- 1
            regEnd <- as.integer(targets["chr07"])
          }
        } else {
          # Fallback to the first chromosome in the user's BAM file
          regChr <- names(targets)[1]
          regStart <- 1
          regEnd <- as.integer(min(50000, targets[1]))
        }
      }
    }, error = function(e) {
      message("Using default documented coordinates due to header reading error: ", e\$message)
    })
    
    message(sprintf("Running analysis on region: %s:%d-%d", regChr, regStart, regEnd))
    
    # 2. Run Indel comparison using indelDiff
    indelDiffDf <- indelDiff(bam1, bam2, refFsa, regChr, regStart, regEnd, pValueCutOff=1, gtDistCutOff=0)
    
    # 3. Sort results by p-value and d-value to identify candidate variants
    if (!is.null(indelDiffDf) && nrow(indelDiffDf) > 0) {
      indelDiffDfSort <- indelDiffDf[order(indelDiffDf\$p.value, indelDiffDf\$d.value), ]
      
      # Write meaningful results to output files
      write.csv(indelDiffDfSort, file = "indel_diff_results.csv", row.names = FALSE)
      saveRDS(indelDiffDfSort, file = "indel_diff_results.rds")
      
      # Generate a diagnostic scatter plot of the results
      tryCatch({
        pdf("indel_diff_plot.pdf")
        # Avoid log10(0) by replacing 0 with a very small non-zero value
        p_vals <- indelDiffDfSort\$p.value
        p_vals[p_vals == 0] <- min(p_vals[p_vals > 0], 1e-10)
        
        plot(-log10(p_vals), indelDiffDfSort\$d.value,
             col = 'brown', pch = 19,
             xlab = "-log10(p-value)", ylab = "d-value (Euclidean distance)",
             main = "Indel Difference Detection")
        dev.off()
      }, error = function(e) {
        message("Could not generate PDF plot: ", e\$message)
      })
      
      message("Analysis completed successfully. Results written to 'indel_diff_results.csv' and 'indel_diff_results.rds'.")
    } else {
      message("No indel differences detected in the specified region. Writing empty outputs.")
      write.csv(data.frame(), file = "indel_diff_results.csv", row.names = FALSE)
      saveRDS(NULL, file = "indel_diff_results.rds")
    }

    writeLines(c(
        '"BIOC_SICTOOLS_INDEL_DIFFERENCE_DETECTION":',
        paste0('    SICtools: ', as.character(packageVersion('SICtools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_indel_difference_detection.csv versions.yml
    """
}

workflow BIOC_SICTOOLS_INDEL_DIFFERENCE_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam1.bam, bam2.bam, ref.fasta ] ]

    main:
    BIOC_SICTOOLS_INDEL_DIFFERENCE_DETECTION(ch_input)

    emit:
    tables   = BIOC_SICTOOLS_INDEL_DIFFERENCE_DETECTION.out.tables
    plots    = BIOC_SICTOOLS_INDEL_DIFFERENCE_DETECTION.out.plots
    objects  = BIOC_SICTOOLS_INDEL_DIFFERENCE_DETECTION.out.objects
    versions = BIOC_SICTOOLS_INDEL_DIFFERENCE_DETECTION.out.versions
}
