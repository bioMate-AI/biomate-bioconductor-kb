#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lemur — lemur_multi_condition_analysis
// Fit a LEMUR model to multi-condition single-cell data, align embeddings, predict differential expression, and identify validated cell neighborhoods showing cons
// Input: glioblastoma_example_data
// Container: quay.io/biocontainers/bioconductor-lemur:1.8.0--r45ha27e39d_0
// R packages: lemur, SingleCellExperiment, tidyverse, uwot
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, dplyr, lemur, tidyverse, uwot
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input
//  * 2. [Core Analysis] Fit the LEMUR model
//  * 3. [Core Analysis] Align corresponding cells across conditions
//  * 4. [Core Analysis] Predict differential expression for a specific contrast
//  * 5. [Core Analysis] Find and validate differential expression neighborhoods
//  * 6. [Core Analysis] Save Results and Generate Outputs

nextflow.enable.dsl = 2

process BIOC_LEMUR_LEMUR_MULTI_CONDITION_ANALYSIS {
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
    .bm_deps <- c("lemur", "SingleCellExperiment", "tidyverse", "uwot", "SummarizedExperiment")
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
    library(lemur)
    library(SummarizedExperiment)
    library(tidyverse)
    library(uwot)
    
    # Set seed for reproducibility
    set.seed(42)
    
    # -----------------------------------------------------------------------------
    # --- Read User Input ---
    # -----------------------------------------------------------------------------
    # The pipeline reads exactly the 'glioblastoma_example_data' file from the working directory.
    # We check for both the unextended filename and the .rds extension.
    input_file <- "glioblastoma_example_data"
    if (!file.exists(input_file) && file.exists(paste0(input_file, ".rds"))) {
      input_file <- paste0(input_file, ".rds")
    }
    
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    message("Reading input SingleCellExperiment object...")
    glioblastoma_example_data <- readRDS(input_file)
    
    # Ensure the object is a SingleCellExperiment
    if (!inherits(glioblastoma_example_data, "SingleCellExperiment")) {
      stop("Error: Input object is not of class 'SingleCellExperiment'.")
    }
    
    # -----------------------------------------------------------------------------
    # --- Fit the LEMUR model ---
    # -----------------------------------------------------------------------------
    message("Fitting LEMUR model...")
    fit <- lemur(glioblastoma_example_data, design = ~ patient_id + condition, n_embedding = 15, test_fraction = 0.5)
    
    # -----------------------------------------------------------------------------
    # --- Align corresponding cells across conditions ---
    # -----------------------------------------------------------------------------
    message("Aligning embeddings using Harmony...")
    fit <- align_harmony(fit)
    
    # -----------------------------------------------------------------------------
    # --- Predict differential expression for a specific contrast ---
    # -----------------------------------------------------------------------------
    message("Predicting differential expression...")
    fit <- test_de(fit, contrast = cond(condition = "panobinostat") - cond(condition = "ctrl"))
    
    # -----------------------------------------------------------------------------
    # --- Find and validate differential expression neighborhoods ---
    # -----------------------------------------------------------------------------
    message("Finding differential expression neighborhoods...")
    neighborhoods <- find_de_neighborhoods(fit, group_by = vars(patient_id, condition))
    
    # -----------------------------------------------------------------------------
    # --- Save Results and Generate Outputs ---
    # -----------------------------------------------------------------------------
    message("Saving results...")
    
    # Save the fit object and neighborhoods object
    saveRDS(fit, "lemur_fit_result.rds")
    saveRDS(neighborhoods, "lemur_neighborhoods.rds")
    
    # Format and save the neighborhoods table as a CSV
    neighborhoods_df <- as_tibble(neighborhoods)
    
    # If rowData contains gene symbols, merge them for better readability
    if (!is.null(rowData(fit)) && all(c("gene_id", "symbol") %in% colnames(rowData(fit)))) {
      gene_annotations <- as_tibble(rowData(fit)) %>% 
        dplyr::select(gene_id, symbol)
      neighborhoods_df <- neighborhoods_df %>%
        left_join(gene_annotations, by = c("name" = "gene_id")) %>%
        relocate(symbol, .before = "name")
    }
    
    # Convert the list column 'neighborhood' (containing cell IDs) to a semicolon-separated string for CSV compatibility
    if ("neighborhood" %in% colnames(neighborhoods_df)) {
      neighborhoods_df <- neighborhoods_df %>%
        mutate(neighborhood = map_chr(neighborhood, ~ paste(.x, collapse = ";")))
    }
    
    # Arrange by significance and write to CSV
    neighborhoods_df <- neighborhoods_df %>% arrange(pval)
    write_csv(neighborhoods_df, "de_neighborhoods_results.csv")
    
    # Generate and save diagnostic and results plots to a PDF
    message("Generating plots...")
    pdf("lemur_analysis_plots.pdf", width = 10, height = 8)
    
    # 1. UMAP of the aligned latent space
    message("Computing UMAP of latent space...")
    umap_coords <- uwot::umap(t(fit\$embedding))
    colnames(umap_coords) <- c("UMAP1", "UMAP2")
    
    umap_df <- as_tibble(fit\$colData) %>%
      mutate(UMAP1 = umap_coords[, 1], UMAP2 = umap_coords[, 2])
    
    p1 <- ggplot(umap_df, aes(x = UMAP1, y = UMAP2)) +
      geom_point(aes(color = patient_id), size = 0.5, alpha = 0.6) +
      facet_wrap(vars(condition)) +
      theme_minimal() +
      labs(title = "UMAP of Aligned Latent Space from LEMUR",
           subtitle = "Cells grouped by patient and faceted by condition",
           x = "UMAP 1", y = "UMAP 2")
    print(p1)
    
    # 2. Volcano plot of the neighborhoods
    p2 <- neighborhoods_df %>%
      drop_na(lfc, pval, adj_pval) %>%
      ggplot(aes(x = lfc, y = -log10(pval))) +
      geom_point(aes(color = adj_pval < 0.1), alpha = 0.6) +
      scale_color_manual(values = c("black", "red"), name = "FDR < 0.1") +
      theme_minimal() +
      labs(title = "Volcano Plot of Identified Neighborhoods",
           x = "Log Fold Change (LFC)", y = "-log10(p-value)")
    print(p2)
    
    # 3. Neighborhood size vs significance
    p3 <- neighborhoods_df %>%
      drop_na(n_cells, pval, adj_pval) %>%
      ggplot(aes(x = n_cells, y = -log10(pval))) +
      geom_point(aes(color = adj_pval < 0.1), alpha = 0.6) +
      scale_color_manual(values = c("black", "red"), name = "FDR < 0.1") +
      theme_minimal() +
      labs(title = "Neighborhood Size vs. Significance",
           x = "Number of Cells in Neighborhood", y = "-log10(p-value)")
    print(p3)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to:")
    message("- lemur_fit_result.rds")
    message("- lemur_neighborhoods.rds")
    message("- de_neighborhoods_results.csv")
    message("- lemur_analysis_plots.pdf")

    writeLines(c(
        '"BIOC_LEMUR_LEMUR_MULTI_CONDITION_ANALYSIS":',
        paste0('    lemur: ', as.character(packageVersion('lemur')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lemur_multi_condition_analysis.csv versions.yml
    """
}

workflow BIOC_LEMUR_LEMUR_MULTI_CONDITION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ glioblastoma_example_data ] ]

    main:
    BIOC_LEMUR_LEMUR_MULTI_CONDITION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LEMUR_LEMUR_MULTI_CONDITION_ANALYSIS.out.tables
    plots    = BIOC_LEMUR_LEMUR_MULTI_CONDITION_ANALYSIS.out.plots
    objects  = BIOC_LEMUR_LEMUR_MULTI_CONDITION_ANALYSIS.out.objects
    versions = BIOC_LEMUR_LEMUR_MULTI_CONDITION_ANALYSIS.out.versions
}
