#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ASGSCA — gsca_association_analysis
// Model and test the association between multiple genotypes and multiple traits using Generalized Structured Component Analysis (GSCA).
// Input: QCAHS1, W0, B0
// Container: quay.io/biocontainers/bioconductor-asgsca:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ASGSCA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the genotype and trait data frame
//  * 2. [Input & Preparation] Define the latent variables and construct the W0 and B0 matrices
//  * 3. [Core Analysis] Run GSCA to estimate weights and path coefficients, and/or perform permutation tests for path significance
//  * 4. [Core Analysis] Extract significant gene-pathway associations from the resulting p-values

nextflow.enable.dsl = 2

process BIOC_ASGSCA_GSCA_ASSOCIATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required library
        library(ASGSCA)
        
        # Helper function to robustly read user input files from the working directory
        read_input <- function(name) {
          extensions <- c(".csv", ".tsv", ".rds", "")
          for (ext in extensions) {
            file_path <- paste0(name, ext)
            if (file.exists(file_path)) {
              if (grepl("\\\\.rds\$", file_path)) {
                val <- readRDS(file_path)
                if (name %in% c("W0", "B0")) {
                  return(as.matrix(val))
                }
                return(val)
              } else {
                # Read as text file (CSV or TSV)
                sep <- if (grepl("\\\\.tsv\$", file_path)) "\t" else ","
                df <- read.csv(file_path, header = TRUE, sep = sep, check.names = FALSE)
                
                if (name %in% c("W0", "B0")) {
                  rownames(df) <- df[, 1]
                  df <- df[, -1, drop = FALSE]
                  return(as.matrix(df))
                } else {
                  # For QCAHS1, check if the first column is non-numeric (e.g., sample IDs)
                  if (ncol(df) > 0 && !is.numeric(df[, 1])) {
                    rownames(df) <- df[, 1]
                    df <- df[, -1, drop = FALSE]
                  }
                  return(df)
                }
              }
            }
          }
          stop(paste("Required input file not found for:", name))
        }
        
        # 1. Prepare the genotype and trait data frame
        QCAHS1 <- read_input("QCAHS1")
        W0 <- read_input("W0")
        B0 <- read_input("B0")
        
        # Extract observed and latent variable names from the mapping matrices
        ObservedVar <- rownames(W0)
        LatentVar <- colnames(W0)
        
        # Ensure the columns of QCAHS1 match the observed variables in number and order
        QCAHS1 <- QCAHS1[, ObservedVar, drop = FALSE]
        
        # 2. Run GSCA to estimate weights and path coefficients (estim = TRUE, path.test = FALSE)
        res_estim <- GSCA(QCAHS1, W0, B0, latent.names = LatentVar, estim = TRUE, path.test = FALSE, path = NULL, nperm = 1000)
        
        # Save estimation results
        write.csv(res_estim\$Weight, "estimated_weights.csv", row.names = TRUE)
        write.csv(res_estim\$Path, "estimated_path_coefficients.csv", row.names = TRUE)
        saveRDS(res_estim, "gsca_results_estim.rds")
        
        # 3. Run GSCA with permutation tests for path significance (estim = TRUE, path.test = TRUE)
        set.seed(2)
        res_full <- GSCA(QCAHS1, W0, B0, latent.names = LatentVar, estim = TRUE, path.test = TRUE, path = NULL, nperm = 1000)
        saveRDS(res_full, "gsca_results_full.rds")
        
        # 4. Extract significant gene-pathway associations from the resulting p-values
        indices <- which(res_full\$pvalues < 0.05, arr.ind = TRUE)
        
        if (nrow(indices) > 0) {
          ind.row <- indices[, 1]
          ind.col <- indices[, 2]
          Significant <- matrix(rep(0, nrow(indices) * 3), ncol = 3)
          colnames(Significant) <- c("Gene", "Pathway", "pval")
          Significant[, 1] <- rownames(res_full\$pvalues)[ind.row]
          Significant[, 2] <- colnames(res_full\$pvalues)[ind.col]
          Significant[, 3] <- res_full\$pvalues[indices]
        } else {
          Significant <- matrix(character(0), ncol = 3)
          colnames(Significant) <- c("Gene", "Pathway", "pval")
        }
        
        # Save significant associations and p-values
        write.csv(Significant, "significant_associations.csv", row.names = FALSE)
        write.csv(res_full\$pvalues, "path_pvalues.csv", row.names = TRUE)
        
        cat("GSCA association analysis completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_ASGSCA_GSCA_ASSOCIATION_ANALYSIS":',
        paste0('    ASGSCA: ', as.character(packageVersion('ASGSCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsca_association_analysis.csv versions.yml
    """
}

workflow BIOC_ASGSCA_GSCA_ASSOCIATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ QCAHS1, W0, B0 ] ]

    main:
    BIOC_ASGSCA_GSCA_ASSOCIATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ASGSCA_GSCA_ASSOCIATION_ANALYSIS.out.tables
    plots    = BIOC_ASGSCA_GSCA_ASSOCIATION_ANALYSIS.out.plots
    objects  = BIOC_ASGSCA_GSCA_ASSOCIATION_ANALYSIS.out.objects
    versions = BIOC_ASGSCA_GSCA_ASSOCIATION_ANALYSIS.out.versions
}
