#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ANCOMBC — ancombc2_advanced_da
// Perform advanced bias-corrected differential abundance analysis with sensitivity analysis, pairwise comparisons, Dunnett's test, and trend analysis.
// Input: microbiome_counts.tsv, sample_metadata.tsv
// Container: quay.io/biocontainers/bioconductor-ancombc:2.12.0--r45hdfd78af_0
// R packages: ANCOMBC, dplyr, lme4, phyloseq, readr
// Bioconductor: 3.20 | R: 4.4
// Requires: ANCOMBC, dplyr, lme4, phyloseq, readr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the microbiome data and metadata (or a phyloseq/TreeSummarizedExperiment object)
//  * 2. [Core Analysis] Run the ancombc2 function with pseudo-count sensitivity analysis and multi-group options enabled
//  * 3. [Core Analysis] Extract primary, pairwise, Dunnett, and trend results

nextflow.enable.dsl = 2

process BIOC_ANCOMBC_ANCOMBC2_ADVANCED_DA {
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
    .bm_deps <- c("ANCOMBC", "dplyr", "lme4", "phyloseq", "readr")
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
            library(readr)
            library(dplyr)
            library(lme4)
            
            # 1. Load the microbiome data and metadata
            message("Reading input files...")
            counts_file <- "microbiome_counts.tsv"
            metadata_file <- "sample_metadata.tsv"
            
            if (!file.exists(counts_file) || !file.exists(metadata_file)) {
              stop("Required input files 'microbiome_counts.tsv' and/or 'sample_metadata.tsv' not found in the working directory.")
            }
            
            # Read counts table (taxa as rows, samples as columns)
            counts <- read.delim(counts_file, row.names = 1, check.names = FALSE)
            
            # Read metadata
            metadata <- read.delim(metadata_file, row.names = 1, check.names = FALSE)
            colnames(metadata) <- make.names(colnames(metadata))
            
            # Construct taxonomy table dynamically
            # Identify taxonomy columns in counts (any non-numeric columns)
            is_num <- sapply(counts, is.numeric)
            tax_cols <- names(counts)[!is_num]
            
            if (length(tax_cols) > 0) {
              tax_mat <- as.matrix(counts[, tax_cols, drop = FALSE])
              rownames(tax_mat) <- rownames(counts)
              counts_mat <- as.matrix(counts[, is_num, drop = FALSE])
              tax_level_arg <- tax_cols[length(tax_cols)] # Use the most specific taxonomy column available
            } else {
              tax_mat <- matrix(rownames(counts), ncol = 1)
              rownames(tax_mat) <- rownames(counts)
              colnames(tax_mat) <- "Taxon"
              counts_mat <- as.matrix(counts)
              tax_level_arg <- NULL
            }
            class(counts_mat) <- "numeric"
            
            # Align samples between counts and metadata
            common_samples <- intersect(colnames(counts_mat), rownames(metadata))
            if (length(common_samples) == 0) {
              stop("No common samples found between counts and metadata.")
            }
            counts_mat <- counts_mat[, common_samples, drop = FALSE]
            metadata <- metadata[common_samples, , drop = FALSE]
            
            # Filter out invalid covariates (constant or all-unique categorical like sample IDs)
            valid_cols <- sapply(metadata, function(x) {
              n_unique <- length(unique(x))
              if (is.numeric(x)) {
                n_unique > 1
              } else {
                n_unique > 1 && n_unique < nrow(metadata)
              }
            })
            if (sum(valid_cols) == 0) {
              stop("No valid covariates found in metadata.")
            }
            metadata <- metadata[, valid_cols, drop = FALSE]
            
            # Ensure covariates are of appropriate types
            for (col in colnames(metadata)) {
              if (is.character(metadata[[col]])) {
                metadata[[col]] <- as.factor(metadata[[col]])
              }
            }
            
            # Identify potential group variables (factors with >= 2 levels)
            factor_cols <- names(metadata)[sapply(metadata, is.factor)]
            if (length(factor_cols) == 0) {
              # If no factors, convert the first column to factor
              group_var <- colnames(metadata)[1]
              metadata[[group_var]] <- as.factor(metadata[[group_var]])
            } else {
              group_var <- factor_cols[1]
            }
            
            if (length(levels(metadata[[group_var]])) < 2) {
              stop("The selected group variable must have at least 2 levels.")
            }
            
            # Dynamically construct the formula using all valid metadata columns
            fix_formula <- paste(colnames(metadata), collapse = " + ")
            
            # Build phyloseq object
            OTU <- otu_table(counts_mat, taxa_are_rows = TRUE)
            SAMP <- sample_data(metadata)
            TAX <- tax_table(tax_mat)
            pseq <- phyloseq(OTU, SAMP, TAX)
            
            # 2. Run the ancombc2 function with pseudo-count sensitivity analysis and multi-group options enabled
            message("Running ANCOM-BC2 advanced differential abundance analysis...")
            set.seed(123)
            
            n_levels <- length(levels(metadata[[group_var]]))
            
            if (n_levels == 3) {
              run_trend <- TRUE
              trend_ctrl <- list(
                contrast = list(
                  matrix(c(1, 0, -1, 1), nrow = 2, byrow = TRUE),
                  matrix(c(-1, 0, 1, -1), nrow = 2, byrow = TRUE),
                  matrix(c(1, 0, 1, -1), nrow = 2, byrow = TRUE)
                ),
                node = list(2, 2, 1),
                B = 100
              )
            } else {
              run_trend <- FALSE
              trend_ctrl <- NULL
            }
            
            output = ancombc2(
              data = pseq, 
              tax_level = tax_level_arg, 
              fix_formula = fix_formula, 
              rand_formula = NULL, 
              p_adj_method = "holm", 
              pseudo_sens = TRUE, 
              prv_cut = 0.10, 
              lib_cut = 1000, 
              s0_perc = 0.05, 
              group = group_var, 
              struc_zero = TRUE, 
              neg_lb = TRUE, 
              alpha = 0.05, 
              n_cl = 2, 
              verbose = TRUE, 
              global = n_levels >= 3, 
              pairwise = n_levels >= 2, 
              dunnet = n_levels >= 3, 
              trend = run_trend, 
              iter_control = list(tol = 1e-2, max_iter = 20, verbose = TRUE), 
              em_control = list(tol = 1e-5, max_iter = 100), 
              lme_control = lme4::lmerControl(), 
              mdfdr_control = list(fwer_ctrl_method = "holm", B = 100), 
              trend_control = trend_ctrl
            )
            
            # 3. Extract primary, pairwise, Dunnett, and trend results
            message("Extracting results...")
            res_prim = output\$res
            res_global = output\$res_global
            res_pair = output\$res_pair
            res_dunn = output\$res_dunn
            res_trend = output\$res_trend
            
            # 4. Write outputs to files
            message("Writing output files...")
            saveRDS(output, "ancombc2_output.rds")
            
            if (!is.null(res_prim)) {
              write_csv(as.data.frame(res_prim), "ancombc2_res_prim.csv")
            }
            if (!is.null(res_global)) {
              write_csv(as.data.frame(res_global), "ancombc2_res_global.csv")
            }
            if (!is.null(res_pair)) {
              write_csv(as.data.frame(res_pair), "ancombc2_res_pair.csv")
            }
            if (!is.null(res_dunn)) {
              write_csv(as.data.frame(res_dunn), "ancombc2_res_dunn.csv")
            }
            if (!is.null(res_trend)) {
              write_csv(as.data.frame(res_trend), "ancombc2_res_trend.csv")
            }
            
            message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_ANCOMBC_ANCOMBC2_ADVANCED_DA":',
        paste0('    ANCOMBC: ', as.character(packageVersion('ANCOMBC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ancombc2_advanced_da.csv versions.yml
    """
}

workflow BIOC_ANCOMBC_ANCOMBC2_ADVANCED_DA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ microbiome_counts.tsv, sample_metadata.tsv ] ]

    main:
    BIOC_ANCOMBC_ANCOMBC2_ADVANCED_DA(ch_input)

    emit:
    tables   = BIOC_ANCOMBC_ANCOMBC2_ADVANCED_DA.out.tables
    plots    = BIOC_ANCOMBC_ANCOMBC2_ADVANCED_DA.out.plots
    objects  = BIOC_ANCOMBC_ANCOMBC2_ADVANCED_DA.out.objects
    versions = BIOC_ANCOMBC_ANCOMBC2_ADVANCED_DA.out.versions
}
