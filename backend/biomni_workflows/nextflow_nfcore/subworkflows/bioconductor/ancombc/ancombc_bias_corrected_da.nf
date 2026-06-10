#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ANCOMBC — ancombc_bias_corrected_da
// Perform bias-corrected differential abundance analysis using the log-linear ANCOM-BC model.
// Input: microbiome_counts.tsv, sample_metadata.tsv
// Container: quay.io/biocontainers/bioconductor-ancombc:2.12.0--r45hdfd78af_0
// R packages: ANCOMBC, phyloseq, tidyverse
// Bioconductor: 3.20 | R: 4.4
// Requires: ANCOMBC, phyloseq, tidyverse
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the microbiome data and metadata (or a phyloseq/TreeSummarizedExperiment object)
//  * 2. [Core Analysis] Run the ancombc function specifying the formula, group variable, and bias correction parameters
//  * 3. [Core Analysis] Extract log fold changes, standard errors, and global test results

nextflow.enable.dsl = 2

process BIOC_ANCOMBC_ANCOMBC_BIAS_CORRECTED_DA {
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
    .bm_deps <- c("ANCOMBC", "phyloseq", "tidyverse")
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
        library(ANCOMBC)
        library(phyloseq)
        library(tidyverse)
        
        # 1. Load the microbiome data and metadata
        if (!file.exists("microbiome_counts.tsv") || !file.exists("sample_metadata.tsv")) {
          stop("Required input files 'microbiome_counts.tsv' or 'sample_metadata.tsv' are missing.")
        }
        
        # Read count matrix
        counts <- read.delim("microbiome_counts.tsv", row.names = 1, check.names = FALSE)
        
        # Read metadata
        metadata <- read.delim("sample_metadata.tsv", row.names = 1, check.names = FALSE)
        
        # Align samples between counts and metadata
        common_samples <- intersect(colnames(counts), rownames(metadata))
        if (length(common_samples) == 0) {
          stop("No common samples found between counts and metadata.")
        }
        counts <- counts[, common_samples, drop = FALSE]
        metadata <- metadata[common_samples, , drop = FALSE]
        
        # Ensure covariates are of correct types
        for (col in colnames(metadata)) {
          if (is.character(metadata[[col]])) {
            metadata[[col]] <- as.factor(metadata[[col]])
          }
        }
        
        # Determine group variable (first factor column, or first column if none)
        factor_cols <- colnames(metadata)[sapply(metadata, is.factor)]
        if (length(factor_cols) > 0) {
          group_var <- factor_cols[1]
        } else {
          group_var <- colnames(metadata)[1]
          metadata[[group_var]] <- as.factor(metadata[[group_var]])
        }
        
        # Construct formula using all metadata columns
        formula_str <- paste(colnames(metadata), collapse = " + ")
        
        # Construct phyloseq object components
        OTU <- otu_table(as.matrix(counts), taxa_are_rows = TRUE)
        SAMP <- sample_data(metadata)
        
        # Create a dummy taxonomy table mapping each taxon to itself as "Family"
        # to satisfy the tax_level = "Family" requirement in the documented code.
        tax_mat <- matrix(rownames(counts), ncol = 1)
        rownames(tax_mat) <- rownames(counts)
        colnames(tax_mat) <- "Family"
        TAX <- tax_table(tax_mat)
        
        # Combine into a single phyloseq object
        pseq <- phyloseq(OTU, SAMP, TAX)
        
        # 2. Run the ancombc function specifying the formula, group variable, and bias correction parameters
        out = ancombc(data = pseq, tax_level = "Family", formula = formula_str, p_adj_method = "holm", prv_cut = 0.10, lib_cut = 1000, group = group_var, struc_zero = TRUE, neg_lb = TRUE, tol = 1e-5, max_iter = 100, conserve = TRUE, alpha = 0.05, global = TRUE, n_cl = 1, verbose = TRUE)
        
        # 3. Extract log fold changes, standard errors, and global test results
        res = out\$res
        res_global = out\$res_global
        
        # 4. Write named output files for the meaningful results
        saveRDS(out, "ancombc_output.rds")
        
        if (!is.null(res)) {
          for (name in names(res)) {
            if (is.data.frame(res[[name]])) {
              write.csv(res[[name]], paste0("ancombc_res_", name, ".csv"), row.names = FALSE)
            }
          }
        }
        
        if (!is.null(res_global)) {
          write.csv(res_global, "ancombc_res_global.csv", row.names = FALSE)
        }
        
        message("ANCOM-BC pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_ANCOMBC_ANCOMBC_BIAS_CORRECTED_DA":',
        paste0('    ANCOMBC: ', as.character(packageVersion('ANCOMBC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ancombc_bias_corrected_da.csv versions.yml
    """
}

workflow BIOC_ANCOMBC_ANCOMBC_BIAS_CORRECTED_DA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ microbiome_counts.tsv, sample_metadata.tsv ] ]

    main:
    BIOC_ANCOMBC_ANCOMBC_BIAS_CORRECTED_DA(ch_input)

    emit:
    tables   = BIOC_ANCOMBC_ANCOMBC_BIAS_CORRECTED_DA.out.tables
    plots    = BIOC_ANCOMBC_ANCOMBC_BIAS_CORRECTED_DA.out.plots
    objects  = BIOC_ANCOMBC_ANCOMBC_BIAS_CORRECTED_DA.out.objects
    versions = BIOC_ANCOMBC_ANCOMBC_BIAS_CORRECTED_DA.out.versions
}
