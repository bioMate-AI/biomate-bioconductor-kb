#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vulcan — rank_enrichment_analysis
// Calculate enrichment of groups of gene sets over a vector of signature values using linear algebraic matrix multiplication.
// Input: signatures.rds, groups.rds
// Container: quay.io/biocontainers/bioconductor-vulcan:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: vulcan
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run Rank Enrichment Analysis using rea

nextflow.enable.dsl = 2

process BIOC_VULCAN_RANK_ENRICHMENT_ANALYSIS {
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
    .bm_deps <- c("vulcan")
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
    library(vulcan)
    
    # Verify that the required input files exist in the working directory
    if (!file.exists("signatures.rds")) {
      stop("Error: 'signatures.rds' not found in the working directory.")
    }
    if (!file.exists("groups.rds")) {
      stop("Error: 'groups.rds' not found in the working directory.")
    }
    
    # Read the user input files
    signatures <- readRDS("signatures.rds")
    groups <- readRDS("groups.rds")
    
    # Validate input formats
    if (!is.numeric(signatures) || is.null(names(signatures))) {
      stop("Error: 'signatures' must be a named numeric vector.")
    }
    if (!is.list(groups) || is.null(names(groups))) {
      stop("Error: 'groups' must be a named list of character vectors.")
    }
    
    # Run Rank Enrichment Analysis using rea (reproducing documented function call exactly)
    obj <- rea(signatures=signatures, groups=groups)
    
    # Save the primary output object as an RDS file
    saveRDS(obj, file = "rea_results.rds")
    
    # Export the results to a CSV file for downstream analysis
    tryCatch({
      if (is.matrix(obj) || is.data.frame(obj)) {
        write.csv(as.data.frame(obj), file = "rea_results.csv", row.names = TRUE)
      } else if (is.vector(obj)) {
        write.csv(data.frame(Group = names(obj), Score = obj), file = "rea_results.csv", row.names = FALSE)
      } else {
        # Fallback to text representation if structure is unexpected
        writeLines(capture.output(print(obj)), con = "rea_results.txt")
      }
    }, error = function(e) {
      warning("Could not write tabular output: ", e\$message)
    })
    
    cat("Rank Enrichment Analysis completed successfully. Outputs saved to 'rea_results.rds' and 'rea_results.csv'.\n")

    writeLines(c(
        '"BIOC_VULCAN_RANK_ENRICHMENT_ANALYSIS":',
        paste0('    vulcan: ', as.character(packageVersion('vulcan')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rank_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_VULCAN_RANK_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ signatures.rds, groups.rds ] ]

    main:
    BIOC_VULCAN_RANK_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VULCAN_RANK_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_VULCAN_RANK_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_VULCAN_RANK_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_VULCAN_RANK_ENRICHMENT_ANALYSIS.out.versions
}
