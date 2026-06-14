#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lefser — phyloseq_integration
// Convert a phyloseq object to a SummarizedExperiment or TreeSummarizedExperiment for compatibility with lefser.
// Input: phyloseq object containing OTU tables and sample data.
// Container: quay.io/biocontainers/bioconductor-lefser:1.20.2--r45hdfd78af_0
// R packages: SummarizedExperiment, lefser, phyloseq
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, lefser, mia, phyloseq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract OTU table and sample data from the phyloseq object
//  * 2. [Visualization & Output] Construct a SummarizedExperiment object, or alternatively use mia::makeTreeSummarizedExperimentFromPhyloseq

nextflow.enable.dsl = 2

process BIOC_LEFSER_PHYLOSEQ_INTEGRATION {
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
    .bm_deps <- c("SummarizedExperiment", "lefser", "phyloseq")
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
    library(phyloseq)
    library(SummarizedExperiment)
    library(lefser)
    
    # Define input file path (expected in the working directory)
    input_file <- "phyloseq_input.rds"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # Load phyloseq object
    kostic <- readRDS(input_file)
    
    # Split data tables
    counts <- unclass(otu_table(kostic))
    coldata <- as(sample_data(kostic), "data.frame")
    
    # Create a SummarizedExperiment object
    se <- SummarizedExperiment(assays = list(counts = counts), colData = coldata)
    
    # Save the SummarizedExperiment object
    saveRDS(se, "summarized_experiment.rds")
    
    # Create a TreeSummarizedExperiment object using mia package (if available/applicable)
    tryCatch({
      if (requireNamespace("mia", quietly = TRUE)) {
        tse <- mia::makeTreeSummarizedExperimentFromPhyloseq(kostic)
        saveRDS(tse, "tree_summarized_experiment.rds")
      } else {
        warning("The 'mia' package is not installed. Skipping TreeSummarizedExperiment creation.")
      }
    }, error = function(e) {
      message("Error creating TreeSummarizedExperiment: ", e\$message)
    })

    writeLines(c(
        '"BIOC_LEFSER_PHYLOSEQ_INTEGRATION":',
        paste0('    lefser: ', as.character(packageVersion('lefser')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phyloseq_integration.csv versions.yml
    """
}

workflow BIOC_LEFSER_PHYLOSEQ_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phyloseq object containing OTU tables and sample data. ] ]

    main:
    BIOC_LEFSER_PHYLOSEQ_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_LEFSER_PHYLOSEQ_INTEGRATION.out.tables
    plots    = BIOC_LEFSER_PHYLOSEQ_INTEGRATION.out.plots
    objects  = BIOC_LEFSER_PHYLOSEQ_INTEGRATION.out.objects
    versions = BIOC_LEFSER_PHYLOSEQ_INTEGRATION.out.versions
}
