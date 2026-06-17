#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clustifyr — marker_list_annotation
// Annotate cell clusters using a table of known marker genes and statistical metrics.
// Input: pbmc_matrix, pbmc_meta, cbmc_m
// Container: quay.io/biocontainers/bioconductor-clustifyr:1.22.0--r45hdfd78af_0
// R packages: clustifyr
// Bioconductor: 3.20 | R: 4.4
// Requires: clustifyr
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate marker-based similarity metrics using clustify_lists
//  * 2. [Visualization & Output] Visualize the results as a heatmap using plot_cor_heatmap
//  * 3. [Core Analysis] Call cell types using cor_to_call
//  * 4. [Core Analysis] Append the called cell types to the metadata using call_to_metadata

nextflow.enable.dsl = 2

process BIOC_CLUSTIFYR_MARKER_LIST_ANNOTATION {
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
    .bm_deps <- c("clustifyr")
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
        library(clustifyr)
        
        # Helper function to robustly find and read input files from the working directory
        find_and_read <- function(base_name, row_names = 1) {
          extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
          for (ext in extensions) {
            file_path <- paste0(base_name, ext)
            if (file.exists(file_path)) {
              # Try reading as RDS first if extension is .rds or if it's a binary file
              if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
                return(readRDS(file_path))
              }
              # Try reading as TSV
              if (grepl("\\\\.tsv\$", file_path, ignore.case = TRUE)) {
                return(read.delim(file_path, header = TRUE, row.names = row_names, check.names = FALSE))
              }
              # Try reading as CSV
              if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) {
                return(read.csv(file_path, header = TRUE, row.names = row_names, check.names = FALSE))
              }
              # Fallback generic readers
              res <- tryCatch(readRDS(file_path), error = function(e) NULL)
              if (!is.null(res)) return(res)
              
              res <- tryCatch(read.csv(file_path, header = TRUE, row.names = row_names, check.names = FALSE), error = function(e) NULL)
              if (!is.null(res)) return(res)
            }
          }
          stop(paste("Error: Required input file matching", base_name, "not found in the working directory."))
        }
        
        # 1. Load User Inputs
        pbmc_matrix <- find_and_read("pbmc_matrix", row_names = 1)
        pbmc_meta   <- find_and_read("pbmc_meta", row_names = 1)
        cbmc_m      <- find_and_read("cbmc_m", row_names = NULL)
        
        # Ensure pbmc_matrix is in matrix format
        if (!is.matrix(pbmc_matrix) && !inherits(pbmc_matrix, "Matrix")) {
          pbmc_matrix <- as.matrix(pbmc_matrix)
        }
        
        # Dynamically determine the cluster column name from the metadata
        cluster_col_name <- colnames(pbmc_meta)[1]
        
        # 2. Calculate marker-based similarity metrics using clustify_lists
        list_res <- clustify_lists(
            input = pbmc_matrix, # matrix of normalized single-cell RNA-seq counts
            metadata = pbmc_meta, # meta.data table containing cell clusters
            cluster_col = cluster_col_name, # name of column in meta.data containing cell clusters
            marker = cbmc_m, # list of known marker genes
            metric = "pct" # test to use for assigning cell types
        )
        
        # Save similarity matrix
        write.csv(as.data.frame(list_res), "marker_similarity_matrix.csv", row.names = TRUE)
        
        # 3. Visualize the results as a heatmap using plot_cor_heatmap
        pdf("marker_heatmap.pdf", width = 8, height = 6)
        p <- plot_cor_heatmap(
            cor_mat = list_res, # matrix of correlation coefficients from clustify_lists()
            cluster_rows = FALSE, # cluster by row?
            cluster_columns = FALSE, # cluster by column?
            legend_title = "% expressed" # title of heatmap legend
        )
        print(p)
        dev.off()
        
        # 4. Call cell types using cor_to_call
        list_res2 <- cor_to_call(
            cor_mat = list_res, # matrix correlation coefficients
            cluster_col = cluster_col_name # name of column in meta.data containing cell clusters
        )
        
        # Save called cell types table
        write.csv(list_res2, "called_cell_types.csv", row.names = FALSE)
        
        # 5. Append the called cell types to the metadata using call_to_metadata
        pbmc_meta3 <- call_to_metadata(
            res = list_res2, # data.frame of called cell type for each cluster
            metadata = pbmc_meta, # original meta.data table containing cell clusters
            cluster_col = cluster_col_name, # name of column in meta.data containing cell clusters
            rename_prefix = "list_" # set a prefix for the new column
        )
        
        # Save final annotated metadata
        write.csv(pbmc_meta3, "annotated_metadata.csv", row.names = TRUE)
        saveRDS(pbmc_meta3, "annotated_metadata.rds")

    writeLines(c(
        '"BIOC_CLUSTIFYR_MARKER_LIST_ANNOTATION":',
        paste0('    clustifyr: ', as.character(packageVersion('clustifyr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_marker_list_annotation.csv versions.yml
    """
}

workflow BIOC_CLUSTIFYR_MARKER_LIST_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc_matrix, pbmc_meta, cbmc_m ] ]

    main:
    BIOC_CLUSTIFYR_MARKER_LIST_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CLUSTIFYR_MARKER_LIST_ANNOTATION.out.tables
    plots    = BIOC_CLUSTIFYR_MARKER_LIST_ANNOTATION.out.plots
    objects  = BIOC_CLUSTIFYR_MARKER_LIST_ANNOTATION.out.objects
    versions = BIOC_CLUSTIFYR_MARKER_LIST_ANNOTATION.out.versions
}
