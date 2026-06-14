#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: marr — maximum_rank_reproducibility_analysis
// Assess reproducibility of high-dimensional biological features and sample pairs, visualize the distributions, and filter the dataset.
// Input: abundance_matrix.csv
// Container: quay.io/biocontainers/bioconductor-marr:1.20.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, marr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute maximum rank reproducibility using Marr()
//  * 2. [Core Analysis] Extract reproducible features and sample pairs using MarrFeatures() and MarrSamplepairs()
//  * 3. [Core Analysis] Check the percentage of reproducible features and sample pairs using MarrFeaturesfiltered() and MarrSamplepairsfiltered()
//  * 4. [Visualization & Output] Plot the distributions using MarrPlotSamplepairs() and MarrPlotFeatures()
//  * 5. [Core Analysis] Filter the dataset by features, sample pairs, or both using MarrFilterData()

nextflow.enable.dsl = 2

process BIOC_MARR_MAXIMUM_RANK_REPRODUCIBILITY_ANALYSIS {
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
    .bm_deps <- c("marr", "SummarizedExperiment")
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
               library(SummarizedExperiment)
 library(marr)
        
        # 1. Read the user input file
        # The input file 'abundance_matrix.csv' is expected to have features as rows and replicate samples as columns.
        abundance_data <- read.csv("abundance_matrix.csv", row.names = 1, check.names = FALSE)
        abundance_matrix <- as.matrix(abundance_data)
        
        # 2. Compute maximum rank reproducibility using Marr()
        Marr_output <- Marr(abundance_matrix, pSamplepairs = 0.75, pFeatures = 0.75, alpha = 0.05)
        
        # Print the summary of the Marr output
        print(Marr_output)
        
        # 3. Extract reproducible features and sample pairs
        features_df <- MarrFeatures(Marr_output)
        samplepairs_df <- MarrSamplepairs(Marr_output)
        
        # Print heads of the extracted tables
        print(head(features_df))
        print(head(samplepairs_df))
        
        # Save the extracted tables to CSV files
        write.csv(features_df, "marr_features.csv", row.names = FALSE)
        write.csv(samplepairs_df, "marr_samplepairs.csv", row.names = FALSE)
        
        # 4. Check the percentage of reproducible features and sample pairs
        pct_features <- MarrFeaturesfiltered(Marr_output)
        pct_samplepairs <- MarrSamplepairsfiltered(Marr_output)
        
        # Print percentages
        print(pct_features)
        print(pct_samplepairs)
        
        # Save percentages to a text file
        writeLines(c(
          paste("Percent of reproducible sample pairs per feature (>75%):", pct_features),
          paste("Percent of reproducible features per sample pair (>75%):", pct_samplepairs)
        ), "reproducibility_percentages.txt")
        
        # 5. Plot the distributions and save to PDF
        pdf("marr_reproducibility_plots.pdf", width = 7, height = 5)
        print(MarrPlotSamplepairs(Marr_output))
        print(MarrPlotFeatures(Marr_output))
        dev.off()
        
        # 6. Filter the dataset by features, sample pairs, or both
        filtered_features <- MarrFilterData(Marr_output, by = "features")
        filtered_samplePairs <- MarrFilterData(Marr_output, by = "samplePairs")
        filtered_both <- MarrFilterData(Marr_output, by = "both")
        
        # Save the filtered objects as RDS files to preserve their structure
        saveRDS(filtered_features, "filtered_by_features.rds")
        saveRDS(filtered_samplePairs, "filtered_by_samplePairs.rds")
        saveRDS(filtered_both, "filtered_by_both.rds")
        
        # Helper function to write filtered datasets to CSV
        save_filtered_csv <- function(obj, filename) {
          if (inherits(obj, "SummarizedExperiment")) {
            # If the output is a SummarizedExperiment, extract the assay
            if (requireNamespace("SummarizedExperiment", quietly = TRUE)) {
              write.csv(SummarizedExperiment::assay(obj), filename)
            } else {
              warning("SummarizedExperiment package not available to extract assay.")
            }
          } else {
            # Otherwise, write as a standard data frame/matrix
            write.csv(as.data.frame(obj), filename)
          }
        }
        
        # Attempt to save filtered datasets as CSV files
        tryCatch({
          save_filtered_csv(filtered_features, "filtered_by_features.csv")
          save_filtered_csv(filtered_samplePairs, "filtered_by_samplePairs.csv")
          save_filtered_csv(filtered_both, "filtered_by_both.csv")
        }, error = function(e) {
          warning("Could not write filtered datasets to CSV: ", e\$message)
        })

    writeLines(c(
        '"BIOC_MARR_MAXIMUM_RANK_REPRODUCIBILITY_ANALYSIS":',
        paste0('    marr: ', as.character(packageVersion('marr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_maximum_rank_reproducibility_analysis.csv versions.yml
    """
}

workflow BIOC_MARR_MAXIMUM_RANK_REPRODUCIBILITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ abundance_matrix.csv ] ]

    main:
    BIOC_MARR_MAXIMUM_RANK_REPRODUCIBILITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MARR_MAXIMUM_RANK_REPRODUCIBILITY_ANALYSIS.out.tables
    plots    = BIOC_MARR_MAXIMUM_RANK_REPRODUCIBILITY_ANALYSIS.out.plots
    objects  = BIOC_MARR_MAXIMUM_RANK_REPRODUCIBILITY_ANALYSIS.out.objects
    versions = BIOC_MARR_MAXIMUM_RANK_REPRODUCIBILITY_ANALYSIS.out.versions
}
