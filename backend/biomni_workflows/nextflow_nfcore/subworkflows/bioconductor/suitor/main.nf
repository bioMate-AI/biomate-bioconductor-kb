#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SUITOR — signature_selection_and_extraction
// Select the optimal number of mutational signatures using cross-validation and extract their profiles and activities.
// Input: mutational_catalog.csv
// Container: quay.io/biocontainers/bioconductor-suitor:1.12.0--r45h01b2380_0
// R packages: MutationalPatterns, SUITOR
// Bioconductor: 3.20 | R: 4.4
// Requires: MutationalPatterns, SUITOR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the mutational catalog data
//  * 2. [Core Analysis] Run suitor() with specified options to perform cross-validation and determine the optimal rank
//  * 3. [Core Analysis] Extract signature profiles (W) and activities (H) using suitorExtractWH() with the selected rank
//  * 4. [Core Analysis] Compare the extracted signatures with COSMIC signatures using MutationalPatterns functions

nextflow.enable.dsl = 2

process BIOC_SUITOR_SIGNATURE_SELECTION_AND_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MutationalPatterns", "SUITOR")
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
        library(SUITOR)
        suppressPackageStartupMessages(library(MutationalPatterns))
        
        # 1. Load the mutational catalog data
        # The pipeline reads mutational_catalog.csv from the working directory
        if (!file.exists("mutational_catalog.csv")) {
          stop("Error: mutational_catalog.csv not found in the working directory.")
        }
        
        SimData <- read.csv("mutational_catalog.csv", row.names = 1, check.names = FALSE)
        SimData <- as.matrix(SimData)
        
        # 2. Run suitor() with specified options to perform cross-validation and determine the optimal rank
        OP  <- list(max.rank=3, k.fold=5, n.starts=4)
        set.seed(123)
        re <- suitor(SimData, op=OP)
        
        # Save cross-validation results and optimal rank
        saveRDS(re, file = "suitor_cv_results.rds")
        writeLines(as.character(re\$rank), con = "optimal_rank.txt")
        
        # 3. Extract signature profiles (W) and activities (H) using suitorExtractWH() with the selected rank
        set.seed(123)
        Extract <- suitorExtractWH(SimData, re\$rank)
        
        # Save extracted profiles and activities
        write.csv(Extract\$W, file = "extracted_signatures_W.csv", row.names = TRUE)
        write.csv(Extract\$H, file = "extracted_activities_H.csv", row.names = TRUE)
        
        # 4. Compare the extracted signatures with COSMIC signatures using MutationalPatterns functions
        COSMIC <- get_known_signatures(source = "COSMIC_v3.2")
        
        # Save the 96-profile plot to a PDF file
        pdf("signature_profile_plot.pdf", width = 10, height = 8)
        print(plot_96_profile(Extract\$W, condensed=TRUE, ymax=0.3))
        dev.off()
        
        # Calculate and save cosine similarity matrix
        CS <- cos_sim_matrix(Extract\$W, COSMIC)
        write.csv(CS, file = "cosine_similarity_COSMIC.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_SUITOR_SIGNATURE_SELECTION_AND_EXTRACTION":',
        paste0('    SUITOR: ', as.character(packageVersion('SUITOR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signature_selection_and_extraction.csv versions.yml
    """
}

workflow BIOC_SUITOR_SIGNATURE_SELECTION_AND_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mutational_catalog.csv ] ]

    main:
    BIOC_SUITOR_SIGNATURE_SELECTION_AND_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_SUITOR_SIGNATURE_SELECTION_AND_EXTRACTION.out.tables
    plots    = BIOC_SUITOR_SIGNATURE_SELECTION_AND_EXTRACTION.out.plots
    objects  = BIOC_SUITOR_SIGNATURE_SELECTION_AND_EXTRACTION.out.objects
    versions = BIOC_SUITOR_SIGNATURE_SELECTION_AND_EXTRACTION.out.versions
}
