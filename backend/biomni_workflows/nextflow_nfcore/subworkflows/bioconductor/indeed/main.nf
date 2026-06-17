#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: INDEED — non_partial_correlation_analysis
// Perform differential network analysis using standard (non-partial) correlation.
// Input: data, class_label, id
// Container: quay.io/biocontainers/bioconductor-indeed:2.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: INDEED
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] READ USER INPUT FILES
//  * 2. [Core Analysis] RUN NON-PARTIAL CORRELATION ANALYSIS
//  * 3. [Core Analysis] WRITE OUTPUTS

nextflow.enable.dsl = 2

process BIOC_INDEED_NON_PARTIAL_CORRELATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("INDEED")
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
    
    # Load required library
    library(INDEED)
    
    # ==========================================
    # --- READ USER INPUT FILES ---
    # ==========================================
    
    # Read expression data matrix (features as rows, subjects as columns)
    if (file.exists("data.csv")) {
      Met_GU <- as.matrix(read.csv("data.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("data.rds")) {
      Met_GU <- readRDS("data.rds")
    } else {
      stop("Error: Required input file 'data.csv' or 'data.rds' not found in the working directory.")
    }
    
    # Read class labels (group labels for each subject)
    if (file.exists("class_label.csv")) {
      # Read as a single-row or single-column CSV and convert to vector
      class_df <- read.csv("class_label.csv", header = FALSE, stringsAsFactors = FALSE)
      Met_Group_GU <- as.vector(unlist(class_df))
    } else if (file.exists("class_label.txt")) {
      Met_Group_GU <- readLines("class_label.txt")
    } else if (file.exists("class_label.rds")) {
      Met_Group_GU <- readRDS("class_label.rds")
    } else {
      stop("Error: Required input file 'class_label.csv', 'class_label.txt', or 'class_label.rds' not found.")
    }
    
    # Read feature IDs (vector of feature IDs)
    if (file.exists("id.csv")) {
      id_df <- read.csv("id.csv", header = FALSE, stringsAsFactors = FALSE)
      Met_name_GU <- as.vector(unlist(id_df))
    } else if (file.exists("id.txt")) {
      Met_name_GU <- readLines("id.txt")
    } else if (file.exists("id.rds")) {
      Met_name_GU <- readRDS("id.rds")
    } else {
      stop("Error: Required input file 'id.csv', 'id.txt', or 'id.rds' not found.")
    }
    
    # Ensure class_label is a vector and matches the number of columns in data
    Met_Group_GU <- as.vector(Met_Group_GU)
    if (ncol(Met_GU) != length(Met_Group_GU)) {
      stop(sprintf("Dimension mismatch: 'data' has %d columns (subjects), but 'class_label' has %d elements.", 
                   ncol(Met_GU), length(Met_Group_GU)))
    }
    
    # Ensure id is a vector and matches the number of rows in data
    Met_name_GU <- as.vector(Met_name_GU)
    if (nrow(Met_GU) != length(Met_name_GU)) {
      stop(sprintf("Dimension mismatch: 'data' has %d rows (features), but 'id' has %d elements.", 
                   nrow(Met_GU), length(Met_name_GU)))
    }
    
    # ==========================================
    # --- RUN NON-PARTIAL CORRELATION ANALYSIS ---
    # ==========================================
    
    # Execute the documented function call exactly as specified
    results <- non_partial_cor(data = Met_GU, class_label = Met_Group_GU, id = Met_name_GU, method = "spearman")
    
    # ==========================================
    # --- WRITE OUTPUTS ---
    # ==========================================
    
    # Save the complete results object as an RDS file
    saveRDS(results, "indeed_results.rds")
    
    # Export tabular results if applicable
    if (is.data.frame(results)) {
      write.csv(results, "indeed_results.csv", row.names = FALSE)
    } else if (is.list(results)) {
      # If the result is a list, attempt to write individual data frames/matrices to CSV
      for (name in names(results)) {
        element <- results[[name]]
        if (is.data.frame(element) || is.matrix(element)) {
          write.csv(element, paste0("indeed_results_", name, ".csv"), row.names = TRUE)
        }
      }
    }
    
    cat("Analysis completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_INDEED_NON_PARTIAL_CORRELATION_ANALYSIS":',
        paste0('    INDEED: ', as.character(packageVersion('INDEED')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_non_partial_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_INDEED_NON_PARTIAL_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data, class_label, id ] ]

    main:
    BIOC_INDEED_NON_PARTIAL_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_INDEED_NON_PARTIAL_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_INDEED_NON_PARTIAL_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_INDEED_NON_PARTIAL_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_INDEED_NON_PARTIAL_CORRELATION_ANALYSIS.out.versions
}
