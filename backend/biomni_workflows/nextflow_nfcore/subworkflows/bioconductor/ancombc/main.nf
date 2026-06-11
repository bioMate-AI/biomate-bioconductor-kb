#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ANCOMBC — ancom_heuristic_da
// Perform differential abundance analysis using the heuristic ANCOM method with ALR transformation.
// Input: microbiome_counts.tsv, sample_metadata.tsv
// Container: quay.io/biocontainers/bioconductor-ancombc:2.12.0--r45hdfd78af_0
// R packages: ANCOMBC, lme4, phyloseq, tidyverse
// Bioconductor: 3.20 | R: 4.4
// Requires: ANCOMBC, lme4, phyloseq, tidyverse
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the microbiome data and metadata (or a phyloseq/TreeSummarizedExperiment object)
//  * 2. [Core Analysis] Run the ancom function specifying the main variable, adjustment formula, and optional random formula
//  * 3. [Core Analysis] Extract the W statistics and test results

nextflow.enable.dsl = 2

process BIOC_ANCOMBC_ANCOM_HEURISTIC_DA {
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
    .bm_deps <- c("ANCOMBC", "lme4", "phyloseq", "tidyverse")
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
            library(lme4)
            
            # 1. Load the microbiome data and metadata
            if (!file.exists("microbiome_counts.tsv") || !file.exists("sample_metadata.tsv")) {
              stop("Required input files 'microbiome_counts.tsv' and/or 'sample_metadata.tsv' not found in the working directory.")
            }
            
            counts = read.delim("microbiome_counts.tsv", row.names = 1, check.names = FALSE)
            metadata = read.delim("sample_metadata.tsv", row.names = 1, check.names = FALSE)
            
            # Align samples between counts and metadata
            common_samples = intersect(colnames(counts), rownames(metadata))
            if (length(common_samples) == 0) {
              # Try matching rows of counts with rows of metadata (if transposed)
              common_samples = intersect(rownames(counts), rownames(metadata))
              if (length(common_samples) > 0) {
                counts = t(counts)
                common_samples = intersect(colnames(counts), rownames(metadata))
              }
            }
            
            if (length(common_samples) == 0) {
              stop("No matching samples found between microbiome_counts.tsv and sample_metadata.tsv")
            }
            
            counts = counts[, common_samples, drop = FALSE]
            metadata = metadata[common_samples, , drop = FALSE]
            
            # Create a dummy taxonomy table with "Family" column to satisfy tax_level = "Family"
            tax_names = rownames(counts)
            tax_mat = matrix(tax_names, nrow = length(tax_names), ncol = 1)
            colnames(tax_mat) = "Family"
            rownames(tax_mat) = tax_names
            tax = phyloseq::tax_table(tax_mat)
            
            # Dynamically assign variables based on metadata columns to avoid faking data
            meta_cols = colnames(metadata)
            if (length(meta_cols) == 0) {
              stop("Metadata must contain at least one column.")
            }
            
            # Cross-sectional variables
            main_var_cs = if ("bmi" %in% meta_cols) "bmi" else meta_cols[1]
            adj_vars_cs = setdiff(meta_cols, main_var_cs)
            adj_formula_cs = if (length(adj_vars_cs) > 0) paste(adj_vars_cs, collapse = " + ") else NULL
            is_cont_cs = is.numeric(metadata[[main_var_cs]])
            
            # Longitudinal variables
            main_var_long = if ("group" %in% meta_cols) "group" else meta_cols[1]
            is_cont_long = is.numeric(metadata[[main_var_long]])
            
            # Construct phyloseq objects
            otu = phyloseq::otu_table(as.matrix(counts), taxa_are_rows = TRUE)
            sam = phyloseq::sample_data(metadata)
            pseq = phyloseq::phyloseq(otu, tax, sam)
            dietswap = pseq
            
            # 2. Run the cross-sectional ANCOM function
            set.seed(123)
            out = ancom(data = pseq, tax_level = "Family", meta_data = NULL, p_adj_method = "holm", prv_cut = 0.10, lib_cut = 1000, main_var = main_var_cs, adj_formula = adj_formula_cs, rand_formula = NULL, lme_control = NULL, struc_zero = !is_cont_cs, neg_lb = !is_cont_cs, alpha = 0.05, n_cl = 2, verbose = TRUE)
            res = out \$ res
            
            # Save cross-sectional results
            write.csv(res, "ancom_cross_sectional_results.csv", row.names = FALSE)
            saveRDS(out, "ancom_cross_sectional_output.rds")
            
            # Generate and save cross-sectional W statistics plot
            tryCatch({
              q_val = out \$ q_data
              beta_val = out \$ beta_data
              beta_val = beta_val * (q_val < 0.05 )
              beta_pos = apply ( abs (beta_val), 2 , which.max)
              beta_max = vapply ( seq_along (beta_pos), function (i) beta_val[beta_pos[i], i], FUN.VALUE = double ( 1 ))
              n_taxa = ifelse ( is.null (out \$ zero_ind), nrow(res), sum ( apply (out \$ zero_ind[, -1, drop = FALSE ], 1 , sum) == 0 ))
              cut_off = 0.7 * (n_taxa - 1 )
              df_fig_w = res %>% dplyr :: mutate ( beta = beta_max, direct = case_when ( detected_0.7 == TRUE & beta > 0 ~ "Positive" , detected_0.7 == TRUE & beta <= 0 ~ "Negative" , TRUE ~ "Not Significant" )) %>% dplyr :: arrange (W)
              df_fig_w \$ taxon = factor (df_fig_w \$ taxon, levels = df_fig_w \$ taxon)
              df_fig_w \$ W = replace (df_fig_w \$ W, is.infinite (df_fig_w \$ W), n_taxa - 1 )
              df_fig_w \$ direct = factor (df_fig_w \$ direct, levels = c ( "Negative" , "Positive" , "Not Significant" ))
              p_w = df_fig_w %>% ggplot ( aes ( x = taxon, y = W, color = direct)) + geom_point ( size = 2 , alpha = 0.6 ) + labs ( x = "Taxon" , y = "W" ) + scale_color_discrete ( name = NULL ) + geom_hline ( yintercept = cut_off, linetype = "dotted" , color = "blue" , size = 1.5 ) + geom_text ( aes ( x = 2 , y = cut_off + 0.5 , label = "W[0.7]" ), size = 5 , vjust = -0.5 , hjust = 0 , color = "orange" , parse = TRUE ) + theme_bw () + theme ( axis.text.x = element_blank (), axis.ticks.x = element_blank (), panel.grid.major = element_blank ())
              ggsave("ancom_cross_sectional_w_plot.pdf", plot = p_w, width = 7, height = 5)
            }, error = function(e) {
              message("Could not generate cross-sectional plot: ", e\$message)
            })
            
            # 3. Run the longitudinal ANCOM function
            tryCatch({
              if (!"subject" %in% colnames(metadata)) {
                stop("Longitudinal analysis requires a 'subject' column in the metadata.")
              }
              
              adj_vars_long = setdiff(colnames(metadata), c(main_var_long, "subject"))
              adj_formula_long = if (length(adj_vars_long) > 0) paste(adj_vars_long, collapse = " + ") else NULL
              
              set.seed(123)
              out = ancom(data = dietswap, tax_level = "Family", p_adj_method = "holm", prv_cut = 0.10, lib_cut = 1000, main_var = main_var_long, adj_formula = adj_formula_long, rand_formula = "(1 | subject)", lme_control = lme4 :: lmerControl(), struc_zero = !is_cont_long, neg_lb = !is_cont_long, alpha = 0.05, n_cl = 2)
              res = out \$ res
              
              # Save longitudinal results
              write.csv(res, "ancom_longitudinal_results.csv", row.names = FALSE)
              saveRDS(out, "ancom_longitudinal_output.rds")
              
              # Generate and save longitudinal W statistics plot
              q_val = out \$ q_data
              beta_val = out \$ beta_data
              beta_val = beta_val * (q_val < 0.05 )
              beta_pos = apply ( abs (beta_val), 2 , which.max)
              beta_max = vapply ( seq_along (beta_pos), function (i) beta_val[beta_pos[i], i], FUN.VALUE = double ( 1 ))
              n_taxa = ifelse ( is.null (out \$ zero_ind), nrow(res), sum ( apply (out \$ zero_ind[, -1, drop = FALSE ], 1 , sum) == 0 ))
              cut_off = 0.7 * (n_taxa - 1 )
              df_fig_w = res %>% dplyr :: mutate ( beta = beta_max, direct = case_when ( detected_0.7 == TRUE & beta > 0 ~ "Positive" , detected_0.7 == TRUE & beta <= 0 ~ "Negative" , TRUE ~ "Not Significant" )) %>% dplyr :: arrange (W)
              df_fig_w \$ taxon = factor (df_fig_w \$ taxon, levels = df_fig_w \$ taxon)
              df_fig_w \$ W = replace (df_fig_w \$ W, is.infinite (df_fig_w \$ W), n_taxa - 1 )
              df_fig_w \$ direct = factor (df_fig_w \$ direct, levels = c ( "Negative" , "Positive" , "Not Significant" ))
              p_w = df_fig_w %>% ggplot ( aes ( x = taxon, y = W, color = direct)) + geom_point ( size = 2 , alpha = 0.6 ) + labs ( x = "Taxon" , y = "W" ) + scale_color_discrete ( name = NULL ) + geom_hline ( yintercept = cut_off, linetype = "dotted" , color = "blue" , size = 1.5 ) + geom_text ( aes ( x = 2 , y = cut_off + 0.5 , label = "W[0.7]" ), size = 5 , vjust = -0.5 , hjust = 0 , color = "orange" , parse = TRUE ) + theme_bw () + theme ( axis.text.x = element_blank (), axis.ticks.x = element_blank (), panel.grid.major = element_blank ())
              ggsave("ancom_longitudinal_w_plot.pdf", plot = p_w, width = 7, height = 5)
            }, error = function(e) {
              message("Could not run longitudinal ANCOM or generate plot: ", e\$message)
            })

    writeLines(c(
        '"BIOC_ANCOMBC_ANCOM_HEURISTIC_DA":',
        paste0('    ANCOMBC: ', as.character(packageVersion('ANCOMBC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ancom_heuristic_da.csv versions.yml
    """
}

workflow BIOC_ANCOMBC_ANCOM_HEURISTIC_DA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ microbiome_counts.tsv, sample_metadata.tsv ] ]

    main:
    BIOC_ANCOMBC_ANCOM_HEURISTIC_DA(ch_input)

    emit:
    tables   = BIOC_ANCOMBC_ANCOM_HEURISTIC_DA.out.tables
    plots    = BIOC_ANCOMBC_ANCOM_HEURISTIC_DA.out.plots
    objects  = BIOC_ANCOMBC_ANCOM_HEURISTIC_DA.out.objects
    versions = BIOC_ANCOMBC_ANCOM_HEURISTIC_DA.out.versions
}
