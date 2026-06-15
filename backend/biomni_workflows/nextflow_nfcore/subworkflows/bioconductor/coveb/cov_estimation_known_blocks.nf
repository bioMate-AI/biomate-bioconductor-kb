#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: covEB — cov_estimation_known_blocks
// Estimate a shrunk covariance matrix when the groupings of variables (e.g., genes in pathways) are known beforehand.
// Input: samplecov, groups
// Container: quay.io/biocontainers/bioconductor-coveb:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: covEB, jsonlite
// Visualizations: image plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the known groups of variables as a list of character vectors
//  * 2. [Core Analysis] Run EBsingle with the groups argument and sample size n to estimate the block-diagonal covariance matrix

nextflow.enable.dsl = 2

process BIOC_COVEB_COV_ESTIMATION_KNOWN_BLOCKS {
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
    .bm_deps <- c("covEB")
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
        library(covEB)
        
        # ----------------------------------------------------------------------
        # 1. Read User Inputs
        # ----------------------------------------------------------------------
        
        # Read samplecov (sample covariance matrix with row and column names)
        if (file.exists("samplecov.rds")) {
          samplecov <- readRDS("samplecov.rds")
        } else if (file.exists("samplecov.csv")) {
          samplecov <- as.matrix(read.csv("samplecov.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("samplecov")) {
          samplecov <- tryCatch({
            as.matrix(read.csv("samplecov", row.names = 1, check.names = FALSE))
          }, error = function(e) {
            readRDS("samplecov")
          })
        } else {
          stop("Required input file 'samplecov' (CSV or RDS) not found in the working directory.")
        }
        
        # Ensure samplecov is a numeric matrix
        samplecov <- as.matrix(samplecov)
        class(samplecov) <- "numeric"
        
        # Read groups (list of character vectors defining the variable groups/blocks)
        if (file.exists("groups.rds")) {
          groups <- readRDS("groups.rds")
        } else if (file.exists("groups.json")) {
          if (!requireNamespace("jsonlite", quietly = TRUE)) {
            install.packages("jsonlite", repos = "https://cloud.r-project.org")
          }
          groups <- jsonlite::read_json("groups.json", simplifyVector = TRUE)
        } else if (file.exists("groups.txt")) {
          lines <- readLines("groups.txt")
          groups <- lapply(lines, function(l) {
            parts <- strsplit(l, "[[:space:],]+")[[1]]
            parts[parts != ""]
          })
        } else if (file.exists("groups")) {
          groups <- tryCatch({
            readRDS("groups")
          }, error = function(e) {
            lines <- readLines("groups")
            lapply(lines, function(l) {
              parts <- strsplit(l, "[[:space:],]+")[[1]]
              parts[parts != ""]
            })
          })
        } else {
          stop("Required input file 'groups' (RDS, JSON, or TXT) not found in the working directory.")
        }
        
        # Read sample size n (number of samples used to calculate the covariance matrix)
        # Default to 500 if not provided via an external file
        n <- 500
        if (file.exists("n.txt")) {
          n <- as.integer(readLines("n.txt")[1])
        } else if (file.exists("n")) {
          n <- as.integer(readLines("n")[1])
        }
        
        # ----------------------------------------------------------------------
        # 2. Run EBsingle with Known Groups
        # ----------------------------------------------------------------------
        
        # Run the empirical Bayes covariance estimation using the known groups
        test2 <- EBsingle(samplecov, groups = groups, n = n)
        
        # ----------------------------------------------------------------------
        # 3. Save Outputs
        # ----------------------------------------------------------------------
        
        # Save the estimated covariance matrix as an RDS object
        saveRDS(test2, file = "estimated_covariance.rds")
        
        # Save the estimated covariance matrix as a CSV file
        write.csv(as.data.frame(test2), file = "estimated_covariance.csv", row.names = TRUE)
        
        # Generate a PDF plot visualizing the estimated covariance matrix
        pdf("covariance_heatmap.pdf", width = 7, height = 7)
        tryCatch({
          # Use a simple heatmap representation
          image(t(test2[nrow(test2):1, ]), main = "Shrunk Covariance Matrix (covEB)", axes = FALSE)
          axis(1, at = seq(0, 1, length.out = ncol(test2)), labels = colnames(test2), las = 2)
          axis(2, at = seq(0, 1, length.out = nrow(test2)), labels = rev(rownames(test2)), las = 2)
        }, error = function(e) {
          warning("Could not generate heatmap plot: ", e\$message)
        })
        dev.off()
        
        cat("Workflow completed successfully. Outputs saved to 'estimated_covariance.rds', 'estimated_covariance.csv', and 'covariance_heatmap.pdf'.\n")

    writeLines(c(
        '"BIOC_COVEB_COV_ESTIMATION_KNOWN_BLOCKS":',
        paste0('    covEB: ', as.character(packageVersion('covEB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cov_estimation_known_blocks.csv versions.yml
    """
}

workflow BIOC_COVEB_COV_ESTIMATION_KNOWN_BLOCKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samplecov, groups ] ]

    main:
    BIOC_COVEB_COV_ESTIMATION_KNOWN_BLOCKS(ch_input)

    emit:
    tables   = BIOC_COVEB_COV_ESTIMATION_KNOWN_BLOCKS.out.tables
    plots    = BIOC_COVEB_COV_ESTIMATION_KNOWN_BLOCKS.out.plots
    objects  = BIOC_COVEB_COV_ESTIMATION_KNOWN_BLOCKS.out.objects
    versions = BIOC_COVEB_COV_ESTIMATION_KNOWN_BLOCKS.out.versions
}
