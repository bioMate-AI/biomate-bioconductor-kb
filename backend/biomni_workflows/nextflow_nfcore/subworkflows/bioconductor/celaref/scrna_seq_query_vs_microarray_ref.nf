#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: celaref — scrna_seq_query_vs_microarray_ref
// Annotate query single-cell RNA-seq clusters by comparing them to a purified cell-type microarray reference dataset.
// Input: counts_filepath.query, cell_info_filepath.query, norm_expression_file, samples_file
// Container: quay.io/biocontainers/bioconductor-celaref:1.28.0--r45hdfd78af_0
// R packages: Matrix, celaref
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, celaref
// Visualizations: violin plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and filter query scRNA-seq data
//  * 2. [Input & Preparation] Run within-experiment differential expression for query
//  * 3. [Input & Preparation] Run within-experiment differential expression for
//  * 4. [Input & Preparation] Compare query to microarray reference using
//  * 5. [Input & Preparation] Generate similarity labels using make_ref_similarity_names

nextflow.enable.dsl = 2

process BIOC_CELAREF_SCRNA_SEQ_QUERY_VS_MICROARRAY_REF {
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
    .bm_deps <- c("Matrix", "celaref")
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
            library(celaref)
            library(Matrix)
            
            # Define the datasets directory as the current working directory
            datasets_dir <- "."
            
            # -----------------------------------------------------------------------------
            # --- Load and filter query scRNA-seq data ---
            # -----------------------------------------------------------------------------
            
            # Read the user-provided query files from the working directory
            counts_query <- read.delim("counts_filepath.query", sep = "\t", header = TRUE, row.names = 1, check.names = FALSE)
            cell_info_query <- read.delim("cell_info_filepath.query", sep = "\t", header = TRUE, check.names = FALSE)
            
            # Create the 10X directory structure expected by load_dataset_10Xdata
            dir.create("10X_pbmc4k/filtered_gene_bc_matrices/GRCh38", recursive = TRUE, showWarnings = FALSE)
            dir.create("10X_pbmc4k/analysis/clustering/kmeans_7_clusters", recursive = TRUE, showWarnings = FALSE)
            
            # Write the sparse matrix in MatrixMarket format
            writeMM(Matrix(as.matrix(counts_query), sparse = TRUE), file = "10X_pbmc4k/filtered_gene_bc_matrices/GRCh38/matrix.mtx")
            
            # Write the barcodes file
            write.table(colnames(counts_query), file = "10X_pbmc4k/filtered_gene_bc_matrices/GRCh38/barcodes.tsv", 
                        sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
            
            # Write the genes files (both .tsv and .csv to ensure compatibility)
            genes_df <- data.frame(ID = rownames(counts_query), Symbol = rownames(counts_query))
            write.table(genes_df, file = "10X_pbmc4k/filtered_gene_bc_matrices/GRCh38/genes.tsv", 
                        sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
            write.table(genes_df, file = "10X_pbmc4k/filtered_gene_bc_matrices/GRCh38/genes.csv", 
                        sep = ",", row.names = FALSE, col.names = FALSE, quote = FALSE)
            
            # Determine barcode and cluster columns from cell metadata
            barcode_col <- if ("cell_sample" %in% colnames(cell_info_query)) "cell_sample" else colnames(cell_info_query)[1]
            cluster_col <- if ("group" %in% colnames(cell_info_query)) "group" else colnames(cell_info_query)[2]
            
            clusters_df <- data.frame(
              Barcode = cell_info_query[[barcode_col]],
              Cluster = cell_info_query[[cluster_col]]
            )
            write.csv(clusters_df, file = "10X_pbmc4k/analysis/clustering/kmeans_7_clusters/clusters.csv", row.names = FALSE, quote = FALSE)
            
            # Load the dataset using the documented 10X loader function
            dataset_se.10X_pbmc4k_k7 <- load_dataset_10Xdata(
               dataset_path   = file.path(datasets_dir, '10X_pbmc4k'),
               dataset_genome = "GRCh38",
               clustering_set = "kmeans_7_clusters",
               id_to_use      = "GeneSymbol")
            
            # Filter cells and low-expression genes
            dataset_se.10X_pbmc4k_k7 <- trim_small_groups_and_low_expression_genes(dataset_se.10X_pbmc4k_k7)
            
            # -----------------------------------------------------------------------------
            # --- Run within-experiment differential expression for query ---
            # -----------------------------------------------------------------------------
            de_table.10X_pbmc4k_k7 <- contrast_each_group_to_the_rest(dataset_se.10X_pbmc4k_k7, dataset_name = "10X_pbmc4k_k7")
            
            # -----------------------------------------------------------------------------
            # --- Run within-experiment differential expression for ---
            # -----------------------------------------------------------------------------
            
            # Read the user-provided microarray reference files
            norm_expression_table.genes <- read.table("norm_expression_file", sep = "\t", header = TRUE, quote = "", comment.char = "", row.names = 1, check.names = FALSE)
            samples_table <- read.table("samples_file", sep = "\t", header = TRUE, quote = "", comment.char = "", check.names = FALSE)
            
            # Determine sample and group columns dynamically
            ma_sample_col <- if ("cell_sample" %in% colnames(samples_table)) "cell_sample" else colnames(samples_table)[1]
            ma_group_col <- if ("group" %in% colnames(samples_table)) "group" else colnames(samples_table)[2]
            
            # Run differential expression for the microarray reference
            de_table.Watkins2009PBMCs <- contrast_each_group_to_the_rest_for_norm_ma_with_limma(
                             norm_expression_table = norm_expression_table.genes,
                             sample_sheet_table    = samples_table,
                             dataset_name          = "Watkins2009PBMCs",
                             sample_name           = ma_sample_col,
                             group_name            = ma_group_col)
            
            # -----------------------------------------------------------------------------
            # --- Compare query to microarray reference using ---
            # -----------------------------------------------------------------------------
            
            # Generate and save the standard ranking violin plot
            pdf("ranking_violin_plot.pdf", width = 10, height = 8)
            print(make_ranking_violin_plot(de_table.test = de_table.10X_pbmc4k_k7, de_table.ref = de_table.Watkins2009PBMCs))
            dev.off()
            
            # Generate and save the log10-transformed ranking violin plot
            pdf("ranking_violin_plot_log10.pdf", width = 10, height = 8)
            print(make_ranking_violin_plot(de_table.test = de_table.10X_pbmc4k_k7, de_table.ref = de_table.Watkins2009PBMCs, log10trans = TRUE))
            dev.off()
            
            # -----------------------------------------------------------------------------
            # --- Generate similarity labels using make_ref_similarity_names ---
            # -----------------------------------------------------------------------------
            label_table.pbmc4k_k7_vs_Watkins2009PBMCs <- make_ref_similarity_names(de_table.10X_pbmc4k_k7, de_table.Watkins2009PBMCs)
            
            # -----------------------------------------------------------------------------
            # Save Outputs and Clean Up
            # -----------------------------------------------------------------------------
            write.csv(label_table.pbmc4k_k7_vs_Watkins2009PBMCs, "similarity_labels.csv", row.names = FALSE)
            saveRDS(de_table.10X_pbmc4k_k7, "de_table_query.rds")
            saveRDS(de_table.Watkins2009PBMCs, "de_table_ref.rds")
            
            # Clean up the temporary 10X directory structure
            unlink("10X_pbmc4k", recursive = TRUE)

    writeLines(c(
        '"BIOC_CELAREF_SCRNA_SEQ_QUERY_VS_MICROARRAY_REF":',
        paste0('    celaref: ', as.character(packageVersion('celaref')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrna_seq_query_vs_microarray_ref.csv versions.yml
    """
}

workflow BIOC_CELAREF_SCRNA_SEQ_QUERY_VS_MICROARRAY_REF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_filepath.query, cell_info_filepath.query, norm_expression_file, samples_file ] ]

    main:
    BIOC_CELAREF_SCRNA_SEQ_QUERY_VS_MICROARRAY_REF(ch_input)

    emit:
    tables   = BIOC_CELAREF_SCRNA_SEQ_QUERY_VS_MICROARRAY_REF.out.tables
    plots    = BIOC_CELAREF_SCRNA_SEQ_QUERY_VS_MICROARRAY_REF.out.plots
    objects  = BIOC_CELAREF_SCRNA_SEQ_QUERY_VS_MICROARRAY_REF.out.objects
    versions = BIOC_CELAREF_SCRNA_SEQ_QUERY_VS_MICROARRAY_REF.out.versions
}
