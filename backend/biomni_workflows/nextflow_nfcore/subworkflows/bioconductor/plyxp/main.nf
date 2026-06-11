#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: plyxp — plyxp_transcriptomics_pipeline
// Perform contextual data manipulation, normalization, filtering, and summarization on a SummarizedExperiment transcriptomics dataset using plyxp's tidy data mask
// Input: counts.csv, coldata.csv
// Container: 1.4.3--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, dplyr, plyxp
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLYXP_PLYXP_TRANSCRIPTOMICS_PIPELINE {
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
    .bm_deps <- c("plyxp", "dplyr")
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
    library(plyxp)
    library(dplyr)
    
    # --- Read input files ---
    # counts.csv: gene_id as the first column, followed by sample columns
    counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between counts.csv and coldata.csv")
    }
    
    counts_mat <- as.matrix(counts_df[, common_samples, drop = FALSE])
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # --- Initialize SummarizedExperiment and wrap with plyxp ---
    se_obj <- SummarizedExperiment(
      assays = list(counts = counts_mat),
      colData = coldata_df
    )
    xp <- new_plyxp(se_obj)
    
    # --- Normalization and Feature Engineering ---
    # Calculate size factors based on library sizes and add to colData
    lib_sizes <- colSums(assay(se(xp), "counts"))
    xp\$size_factor <- lib_sizes / mean(lib_sizes)
    
    # Scale counts and compute row-wise statistics using plyxp's contextual masking
    xp <- xp |>
      mutate(
        scaled_counts = counts / .cols\$size_factor,
        rows(mean_scaled = rowMeans(.assays_asis\$scaled_counts))
      )
    
    # Categorize genes into expression classes (High vs Low) based on median expression
    xp <- xp |>
      mutate(
        rows(expr_class = ifelse(mean_scaled > median(mean_scaled), "High", "Low"))
      )
    
    # --- Filtering and Grouped Summarization ---
    # Filter out low-abundance genes using the row context
    xp_filtered <- xp |>
      filter(rows(mean_scaled > 0.5))
    
    # Group by expression class and summarize scaled counts per sample
    summary_xp <- xp_filtered |>
      group_by(rows(expr_class)) |>
      summarize(
        sum_scaled = colSums(scaled_counts),
        rows(.features = unique(expr_class))
      )
    
    # Extract the underlying SummarizedExperiment objects
    final_se <- se(xp_filtered)
    summary_se <- se(summary_xp)
    
    # --- Save Outputs ---
    # 1. Save the filtered SummarizedExperiment object
    saveRDS(final_se, "filtered_se.rds")
    
    # 2. Save the summarized expression class matrix
    summary_df <- as.data.frame(assay(summary_se, "sum_scaled"))
    write.csv(summary_df, "expression_class_summary.csv", row.names = TRUE)
    
    # 3. Generate diagnostic plots
    pdf("diagnostic_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # Plot 1: Library sizes vs Size Factors
    plot(lib_sizes, xp\$size_factor,
         xlab = "Library Size (Total Counts)",
         ylab = "Size Factor",
         main = "Library Size vs Size Factor",
         col = "blue", pch = 19)
    abline(h = 1, lty = 2, col = "red")
    
    # Plot 2: Boxplot of scaled counts across samples
    boxplot(log1p(assay(final_se, "scaled_counts")),
            las = 2,
            main = "Log1p Scaled Counts per Sample",
            ylab = "Log1p(Scaled Counts)",
            col = "lightgreen")
    
    dev.off()

    writeLines(c(
        '"BIOC_PLYXP_PLYXP_TRANSCRIPTOMICS_PIPELINE":',
        paste0('    plyxp: ', as.character(packageVersion('plyxp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plyxp_transcriptomics_pipeline.csv versions.yml
    """
}

workflow BIOC_PLYXP_PLYXP_TRANSCRIPTOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PLYXP_PLYXP_TRANSCRIPTOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PLYXP_PLYXP_TRANSCRIPTOMICS_PIPELINE.out.tables
    plots    = BIOC_PLYXP_PLYXP_TRANSCRIPTOMICS_PIPELINE.out.plots
    objects  = BIOC_PLYXP_PLYXP_TRANSCRIPTOMICS_PIPELINE.out.objects
    versions = BIOC_PLYXP_PLYXP_TRANSCRIPTOMICS_PIPELINE.out.versions
}
