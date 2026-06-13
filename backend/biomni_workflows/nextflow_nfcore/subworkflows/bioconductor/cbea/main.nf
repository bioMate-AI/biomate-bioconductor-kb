#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CBEA — cbea_taxa_set_enrichment
// Perform competitive balance enrichment analysis on microbiome taxonomic abundance data to obtain sample-specific enrichment scores for predefined taxa sets.
// Input: abundance_matrix.csv, taxa_sets.gmt
// Container: quay.io/biocontainers/bioconductor-cbea:1.6.0--r44he5774e6_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CBEA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the CBEA package and input datasets
//  * 2. [Core Analysis] Format the taxa sets into a list or BiocSet object
//  * 3. [Core Analysis] Run the cbea function to calculate enrichment scores (z-scores or CDF values) using the specified null distribution and adjustment
//  * 4. [Core Analysis] Extract the resulting enrichment score matrix for downstream statistical analysis

nextflow.enable.dsl = 2

process BIOC_CBEA_CBEA_TAXA_SET_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("CBEA")
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
        
        # 1. Load the CBEA package and input datasets
        library(CBEA)
        
        # Read the abundance matrix (samples as rows, taxa as columns)
        # We assume the first column contains the sample names/IDs
        abundance_data <- as.matrix(read.csv("abundance_matrix.csv", row.names = 1, check.names = FALSE))
        
        # 2. Format the taxa sets into a list
        # Helper function to read GMT file into a list of character vectors
        read_gmt <- function(file_path) {
          con <- file(file_path, "r")
          gmt_list <- list()
          while (TRUE) {
            line <- readLines(con, n = 1)
            if (length(line) == 0) {
              break
            }
            parts <- strsplit(line, "\t")[[1]]
            if (length(parts) >= 3) {
              set_name <- parts[1]
              # parts[2] is typically the description/source, which we skip
              taxa <- parts[3:length(parts)]
              # Clean up any empty elements
              taxa <- taxa[taxa != ""]
              gmt_list[[set_name]] <- taxa
            }
          }
          close(con)
          return(gmt_list)
        }
        
        taxa_sets <- read_gmt("taxa_sets.gmt")
        
        # 3. Run the cbea function to calculate enrichment scores
        # Using the exact documented function call and arguments
        results <- cbea(
          obj = abundance_data, 
          set = taxa_sets, 
          output = "zscore", 
          distr = "norm", 
          adj = FALSE, 
          parametric = TRUE
        )
        
        # 4. Extract and save the resulting enrichment score matrix
        # Convert to data frame for clean CSV export
        results_df <- as.data.frame(results)
        
        # Write outputs to the working directory
        write.csv(results_df, "cbea_enrichment_scores.csv", row.names = TRUE)
        saveRDS(results, "cbea_results.rds")

    writeLines(c(
        '"BIOC_CBEA_CBEA_TAXA_SET_ENRICHMENT":',
        paste0('    CBEA: ', as.character(packageVersion('CBEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cbea_taxa_set_enrichment.csv versions.yml
    """
}

workflow BIOC_CBEA_CBEA_TAXA_SET_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ abundance_matrix.csv, taxa_sets.gmt ] ]

    main:
    BIOC_CBEA_CBEA_TAXA_SET_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_CBEA_CBEA_TAXA_SET_ENRICHMENT.out.tables
    plots    = BIOC_CBEA_CBEA_TAXA_SET_ENRICHMENT.out.plots
    objects  = BIOC_CBEA_CBEA_TAXA_SET_ENRICHMENT.out.objects
    versions = BIOC_CBEA_CBEA_TAXA_SET_ENRICHMENT.out.versions
}
