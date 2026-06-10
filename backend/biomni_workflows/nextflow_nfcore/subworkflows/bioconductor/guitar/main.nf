#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Guitar — guitar_plot_from_bed
// Generate transcriptomic landmark-guided distribution plots of genomic features from BED files using a TxDb object.
// Input: stBedFiles, txdb_file
// Container: quay.io/biocontainers/bioconductor-guitar:2.26.0--r45hdfd78af_0
// R packages: GenomicFeatures, Guitar
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, Guitar
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the TxDb annotation database
//  * 2. [Input & Preparation] Define the list of BED files
//  * 3. [Visualization & Output] Generate the Guitar plot using GuitarPlot with custom parameters

nextflow.enable.dsl = 2

process BIOC_GUITAR_GUITAR_PLOT_FROM_BED {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("GenomicFeatures", "Guitar")
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
    library(Guitar)
    library(GenomicFeatures)
    
    # Parse command-line arguments
    args <- commandArgs(trailingOnly = TRUE)
    sqlite_idx <- grep("\\\\.sqlite\$", args, ignore.case = TRUE)
    if (length(sqlite_idx) > 0) {
      txdb_file <- args[sqlite_idx[1]]
      bed_files <- args[-sqlite_idx[1]]
    } else {
      txdb_file <- args[1]
      bed_files <- args[-1]
    }
    
    # Stage 1: Define the list of BED files from the working directory
    stBedFiles <- as.list(bed_files)
    
    # Stage 2: Load the TxDb annotation database from the working directory
    txdb <- loadDb(txdb_file)
    
    # Stage 3: Generate the Guitar plot using GuitarPlot with custom parameters
    # This function automatically saves a PDF plot in the working directory (e.g., "Guitar_mrna.pdf")
    gplot <- GuitarPlot(txTxdb = txdb, 
                        stBedFiles = stBedFiles,
                        headOrtail = TRUE,
                        enableCI = FALSE,
                        mapFilterTranscript = TRUE,
                        pltTxType =  c("mrna"),
                        stGroupName = gsub("\\\\.[^.]*\$", "", basename(unlist(stBedFiles))))
    
    # Save the resulting ggplot object as an RDS file
    saveRDS(gplot, "guitar_plot.rds")

    writeLines(c(
        '"BIOC_GUITAR_GUITAR_PLOT_FROM_BED":',
        paste0('    Guitar: ', as.character(packageVersion('Guitar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_guitar_plot_from_bed.csv versions.yml
    """
}

workflow BIOC_GUITAR_GUITAR_PLOT_FROM_BED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ stBedFiles, txdb_file ] ]

    main:
    BIOC_GUITAR_GUITAR_PLOT_FROM_BED(ch_input)

    emit:
    tables   = BIOC_GUITAR_GUITAR_PLOT_FROM_BED.out.tables
    plots    = BIOC_GUITAR_GUITAR_PLOT_FROM_BED.out.plots
    objects  = BIOC_GUITAR_GUITAR_PLOT_FROM_BED.out.objects
    versions = BIOC_GUITAR_GUITAR_PLOT_FROM_BED.out.versions
}
