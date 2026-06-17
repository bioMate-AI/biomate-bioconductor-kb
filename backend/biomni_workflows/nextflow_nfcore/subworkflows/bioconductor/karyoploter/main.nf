#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: karyoploteR — plot_genomic_regions
// Plot genomic regions of interest (such as copy number gains and losses) as solid stacked rectangles along the genome.
// Input: gains, losses
// Container: quay.io/biocontainers/bioconductor-karyoploter:1.36.0--r45hdfd78af_0
// R packages: GenomicRanges, karyoploteR, knitr, magrittr, regioneR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, karyoploteR, regioneR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Convert data frames to GRanges objects using toGRanges. 2. Initialize the karyotype plot with plotKaryotype. 3. Plot gains with kp

nextflow.enable.dsl = 2

process BIOC_KARYOPLOTER_PLOT_GENOMIC_REGIONS {
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
    .bm_deps <- c("GenomicRanges", "karyoploteR", "knitr", "magrittr", "regioneR")
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
    library(karyoploteR)
    library(regioneR)
    library(GenomicRanges)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read user input files and convert to GRanges
    # -----------------------------------------------------------------------------
    
    # The pipeline expects 'gains.csv' and 'losses.csv' in the working directory.
    # These files should contain genomic coordinates (e.g., columns: chr, start, end).
    
    gains_file <- "gains.csv"
    losses_file <- "losses.csv"
    
    if (!file.exists(gains_file)) {
      stop(paste("Required input file missing:", gains_file))
    }
    
    if (!file.exists(losses_file)) {
      stop(paste("Required input file missing:", losses_file))
    }
    
    # Read the input data frames
    gains_df <- read.csv(gains_file, stringsAsFactors = FALSE)
    losses_df <- read.csv(losses_file, stringsAsFactors = FALSE)
    
    # Convert data frames to GRanges objects using toGRanges
    gains <- toGRanges(gains_df)
    losses <- toGRanges(losses_df)
    
    # Save the GRanges objects as RDS for downstream utility
    saveRDS(gains, "gains_granges.rds")
    saveRDS(losses, "losses_granges.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 2, 3, & 4: Initialize plot and plot genomic regions
    # -----------------------------------------------------------------------------
    
    # Open a PDF device to save the generated karyotype plot
    pdf("karyoplot_regions.pdf", width = 12, height = 8)
    
    # Initialize the karyotype plot with plotKaryotype
    kp <- plotKaryotype(genome="hg19")
    
    # Plot gains with kpPlotRegions
    kpPlotRegions(kp, gains, col="#FFAACC")
    
    # Plot losses with kpPlotRegions
    kpPlotRegions(kp, losses, col="#CCFFAA")
    
    # Close the PDF device
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved:\n")
    cat("- gains_granges.rds\n")
    cat("- losses_granges.rds\n")
    cat("- karyoplot_regions.pdf\n")

    writeLines(c(
        '"BIOC_KARYOPLOTER_PLOT_GENOMIC_REGIONS":',
        paste0('    karyoploteR: ', as.character(packageVersion('karyoploteR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plot_genomic_regions.csv versions.yml
    """
}

workflow BIOC_KARYOPLOTER_PLOT_GENOMIC_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gains, losses ] ]

    main:
    BIOC_KARYOPLOTER_PLOT_GENOMIC_REGIONS(ch_input)

    emit:
    tables   = BIOC_KARYOPLOTER_PLOT_GENOMIC_REGIONS.out.tables
    plots    = BIOC_KARYOPLOTER_PLOT_GENOMIC_REGIONS.out.plots
    objects  = BIOC_KARYOPLOTER_PLOT_GENOMIC_REGIONS.out.objects
    versions = BIOC_KARYOPLOTER_PLOT_GENOMIC_REGIONS.out.versions
}
