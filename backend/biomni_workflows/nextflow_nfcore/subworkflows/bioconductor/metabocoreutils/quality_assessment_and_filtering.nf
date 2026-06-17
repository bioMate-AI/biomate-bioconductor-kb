#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboCoreUtils — quality_assessment_and_filtering
// Calculate quality control metrics (coefficient of variation, D-ratio, missing value percentage, blank contamination) and filter out low-quality features.
// Input: metabolomics_data, qc_samples, blank_samples
// Container: quay.io/biocontainers/bioconductor-metabocoreutils:1.18.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboCoreUtils
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate coefficient of variation using rowRsd
//  * 2. [Core Analysis] Calculate dispersion ratio (D-ratio) using rowDratio
//  * 3. [Core Analysis] Calculate percentage of missing values using rowPercentMissing
//  * 4. [Core Analysis] Detect solvent contamination using rowBlank
//  * 5. [Core Analysis] Filter the feature matrix based on defined thresholds

nextflow.enable.dsl = 2

process BIOC_METABOCOREUTILS_QUALITY_ASSESSMENT_AND_FILTERING {
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
    .bm_deps <- c("MetaboCoreUtils")
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
    
    # Load required library
    library(MetaboCoreUtils)
    
    # Helper function to read input matrices from the working directory
    read_matrix <- function(base_name) {
      possible_files <- c(
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt"),
        base_name
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          sep <- if (grepl("\\\\.csv\$", f)) "," else if (grepl("\\\\.(tsv|txt)\$", f)) "\t" else ","
          df <- read.table(f, header = TRUE, sep = sep, row.names = 1, check.names = FALSE)
          return(as.matrix(df))
        }
      }
      stop(paste("Required input file not found for:", base_name))
    }
    
    # 1. Read user input files
    metabolomics_data <- read_matrix("metabolomics_data")
    qc_samples <- read_matrix("qc_samples")
    blank_samples <- read_matrix("blank_samples")
    
    # 2. Calculate and display the coefficient of variation
    cv_result <- rowRsd(metabolomics_data)
    
    # 3. Calculate D-ratio and display the result
    dratio_result <- rowDratio(metabolomics_data, qc_samples)
    
    # 4. Calculate and display the percentage of missing values
    missing_result <- rowPercentMissing(metabolomics_data)
    
    # 5. Detect rows where mean(test) > 2 * mean(blank)
    blank_detection_result <- rowBlank(metabolomics_data, blank_samples)
    
    # 6. Set filtering thresholds
    cv_threshold <- 8
    dratio_threshold <- 0.8
    
    # 7. Apply filters
    filtered_data <- metabolomics_data[
      cv_result <= cv_threshold &
      dratio_result <= dratio_threshold &
      missing_result <= 10 &
      !blank_detection_result, , drop = FALSE]
    
    # 8. Write outputs
    # Save the filtered data matrix
    write.csv(filtered_data, "filtered_metabolomics_data.csv", row.names = TRUE)
    saveRDS(filtered_data, "filtered_metabolomics_data.rds")
    
    # Save a comprehensive QC metrics summary table
    qc_metrics <- data.frame(
      Feature = rownames(metabolomics_data),
      CV = cv_result,
      D_ratio = dratio_result,
      Percent_Missing = missing_result,
      Blank_Contamination = blank_detection_result,
      Passed_Filter = (cv_result <= cv_threshold &
                       dratio_result <= dratio_threshold &
                       missing_result <= 10 &
                       !blank_detection_result),
      stringsAsFactors = FALSE
    )
    write.csv(qc_metrics, "qc_metrics_summary.csv", row.names = FALSE)
    
    # Generate diagnostic plots
    pdf("qc_metrics_plots.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2))
    
    # CV Distribution
    hist(cv_result, main = "Coefficient of Variation (CV)", xlab = "CV", col = "skyblue", border = "white")
    abline(v = cv_threshold, col = "red", lty = 2, lwd = 2)
    
    # D-ratio Distribution
    hist(dratio_result, main = "D-ratio", xlab = "D-ratio", col = "lightgreen", border = "white")
    abline(v = dratio_threshold, col = "red", lty = 2, lwd = 2)
    
    # Missingness Distribution
    hist(missing_result, main = "Percent Missing", xlab = "% Missing", col = "salmon", border = "white")
    abline(v = 10, col = "red", lty = 2, lwd = 2)
    
    # Blank Contamination
    barplot(table(blank_detection_result), main = "Blank Contamination Detection",
            col = c("lightgray", "coral"), names.arg = c("Passed", "Contaminated"))
    
    dev.off()

    writeLines(c(
        '"BIOC_METABOCOREUTILS_QUALITY_ASSESSMENT_AND_FILTERING":',
        paste0('    MetaboCoreUtils: ', as.character(packageVersion('MetaboCoreUtils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quality_assessment_and_filtering.csv versions.yml
    """
}

workflow BIOC_METABOCOREUTILS_QUALITY_ASSESSMENT_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metabolomics_data, qc_samples, blank_samples ] ]

    main:
    BIOC_METABOCOREUTILS_QUALITY_ASSESSMENT_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_METABOCOREUTILS_QUALITY_ASSESSMENT_AND_FILTERING.out.tables
    plots    = BIOC_METABOCOREUTILS_QUALITY_ASSESSMENT_AND_FILTERING.out.plots
    objects  = BIOC_METABOCOREUTILS_QUALITY_ASSESSMENT_AND_FILTERING.out.objects
    versions = BIOC_METABOCOREUTILS_QUALITY_ASSESSMENT_AND_FILTERING.out.versions
}
