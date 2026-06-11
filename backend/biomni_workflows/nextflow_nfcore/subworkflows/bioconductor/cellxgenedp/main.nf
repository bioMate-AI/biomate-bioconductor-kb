#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cellxgenedp — cellxgenedp_reference_comparison
// Query the CELLxGENE database to find a matching human reference dataset, download its H5AD file, and perform a comparative gene expression analysis against loca
// Input: counts.csv, coldata.csv
// Container: 1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, cellxgenedp, dplyr, zellkonverter
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLXGENEDP_CELLXGENEDP_REFERENCE_COMPARISON {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(cellxgenedp)
    library(dplyr)
    library(zellkonverter)
    
    # 1. Read local input files
    counts_file <- "counts.csv"
    coldata_file <- "coldata.csv"
    
    if (!file.exists(counts_file) || !file.exists(coldata_file)) {
      stop("Required input files counts.csv and coldata.csv are missing.")
    }
    
    message("Reading local counts and coldata...")
    counts <- read.csv(counts_file, row.names = 1, check.names = FALSE)
    coldata <- read.csv(coldata_file, row.names = 1)
    
    # Create local SingleCellExperiment object
    local_sce <- SingleCellExperiment(
      assays = list(counts = as.matrix(counts)),
      colData = coldata
    )
    
    # 2. Initialize CELLxGENE database
    message("Connecting to CELLxGENE database...")
    cellxgene_db <- db()
    
    # 3. Query and filter for a matching reference dataset
    message("Querying CELLxGENE datasets...")
    datasets_df <- datasets(cellxgene_db)
    
    # Find a small human dataset with H5AD file available to use as reference
    selected_dataset <- datasets_df |>
      filter(
        facets_filter(organism, "label", "Homo sapiens"),
        cell_count < 2000,
        cell_count > 50
      ) |>
      slice(1)
    
    if (nrow(selected_dataset) == 0) {
      message("No small human dataset found. Falling back to the first available dataset.")
      selected_dataset <- datasets_df |> slice(1)
    }
    
    # Get the file information for the selected dataset
    selected_files <- left_join(
      selected_dataset |> select(dataset_id),
      files(cellxgene_db),
      by = "dataset_id"
    ) |>
      filter(filetype == "H5AD") |>
      slice(1)
    
    # Write reference metadata to output
    write.csv(as.data.frame(selected_dataset), "reference_metadata.csv", row.names = FALSE)
    
    # 4. Download and compare (with tryCatch for network robustness)
    comparison_results <- data.frame(
      Gene = character(),
      Local_Mean = numeric(),
      Ref_Mean = numeric(),
      stringsAsFactors = FALSE
    )
    
    correlation_value <- NA
    
    tryCatch({
      if (nrow(selected_files) > 0) {
        message("Downloading reference dataset: ", selected_files\$dataset_id)
        local_h5ad_path <- files_download(selected_files, dry.run = FALSE)
    
        message("Reading reference H5AD file...")
        ref_sce <- readH5AD(local_h5ad_path, use_hdf5 = TRUE, reader = "R")
    
        # Find common genes between local and reference datasets
        common_genes <- intersect(rownames(local_sce), rownames(ref_sce))
    
        if (length(common_genes) > 0) {
          message("Comparing expression of ", length(common_genes), " common genes...")
          local_avg <- rowMeans(assay(local_sce, "counts")[common_genes, , drop = FALSE])
    
          # Extract reference counts (usually stored in assay "X")
          ref_counts <- assay(ref_sce, "X")
          ref_avg <- rowMeans(as.matrix(ref_counts[common_genes, , drop = FALSE]))
    
          comparison_results <- data.frame(
            Gene = common_genes,
            Local_Mean = local_avg,
            Ref_Mean = ref_avg,
            stringsAsFactors = FALSE
          )
    
          correlation_value <- cor(local_avg, ref_avg, method = "spearman")
          message("Spearman correlation: ", correlation_value)
        } else {
          message("No common genes found between local data and reference.")
        }
      } else {
        message("No matching H5AD files found for the selected dataset.")
      }
    }, error = function(e) {
      warning("An error occurred during download or comparison: ", e\$message)
    })
    
    # Write comparison results to output
    write.csv(comparison_results, "gene_comparison.csv", row.names = FALSE)
    
    # Write correlation summary to output
    summary_df <- data.frame(
      Metric = c("Common_Genes_Count", "Spearman_Correlation"),
      Value = c(nrow(comparison_results), ifelse(is.na(correlation_value), "NA", as.character(correlation_value)))
    )
    write.csv(summary_df, "comparison_summary.csv", row.names = FALSE)
    
    # 5. Generate visualization
    pdf("expression_correlation_plot.pdf", width = 6, height = 6)
    if (nrow(comparison_results) > 0 && !is.na(correlation_value)) {
      plot(
        comparison_results\$Local_Mean,
        comparison_results\$Ref_Mean,
        xlab = "Local Mean Expression",
        ylab = "Reference Mean Expression",
        main = paste0("Gene Expression Correlation (r = ", round(correlation_value, 3), ")"),
        pch = 16,
        col = rgb(0.1, 0.2, 0.8, 0.5)
      )
      abline(a = 0, b = 1, col = "red", lty = 2)
    } else {
      plot(
        1, 1,
        type = "n",
        xlab = "",
        ylab = "",
        main = "No Correlation Data Available"
      )
      text(1, 1, "Could not compare local and reference datasets.\nCheck network connection or gene IDs.")
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CELLXGENEDP_CELLXGENEDP_REFERENCE_COMPARISON":',
        paste0('    cellxgenedp: ', as.character(packageVersion('cellxgenedp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellxgenedp_reference_comparison.csv versions.yml
    """
}

workflow BIOC_CELLXGENEDP_CELLXGENEDP_REFERENCE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CELLXGENEDP_CELLXGENEDP_REFERENCE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CELLXGENEDP_CELLXGENEDP_REFERENCE_COMPARISON.out.tables
    plots    = BIOC_CELLXGENEDP_CELLXGENEDP_REFERENCE_COMPARISON.out.plots
    objects  = BIOC_CELLXGENEDP_CELLXGENEDP_REFERENCE_COMPARISON.out.objects
    versions = BIOC_CELLXGENEDP_CELLXGENEDP_REFERENCE_COMPARISON.out.versions
}
