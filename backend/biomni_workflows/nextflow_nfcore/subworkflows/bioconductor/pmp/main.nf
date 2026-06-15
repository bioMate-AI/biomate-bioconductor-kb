#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pmp — metabolomics_filtering_and_normalization
// Filter, normalize, impute, and scale a metabolomics peak matrix to prepare it for downstream statistical analysis.
// Input: MTBLS79
// Container: quay.io/biocontainers/bioconductor-pmp:1.22.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: S4Vectors, SummarizedExperiment, pmp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter samples by missing value percentage using filter_samples_by_mv
//  * 2. [Core Analysis] Filter peaks by fraction of missing values in QC samples using filter_peaks_by_fraction
//  * 3. [Core Analysis] Filter peaks by fraction of missing values across all samples using filter_peaks_by_fraction
//  * 4. [Core Analysis] Filter peaks by relative standard deviation (RSD) in QC samples using filter_peaks_by_rsd
//  * 5. [Core Analysis] Track processing history using processing_history
//  * 6. [Core Analysis] Normalize data using probabilistic quotient normalization with pqn_normalisation
//  * 7. [Core Analysis] Impute missing values using mv_imputation
//  * 8. [Core Analysis] Perform generalized logarithm transformation using glog_transformation
//  * 9. [Visualization & Output] Plot optimized lambda for glog transformation using glog_plot_optimised_lambda

nextflow.enable.dsl = 2

process BIOC_PMP_METABOLOMICS_FILTERING_AND_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("pmp", "S4Vectors", "SummarizedExperiment")
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
    library(pmp)
    library(SummarizedExperiment)
    library(S4Vectors)
    
    # 1. Read input file
    if (file.exists("MTBLS79")) {
      MTBLS79 <- readRDS("MTBLS79")
    } else if (file.exists("MTBLS79.rds")) {
      MTBLS79 <- readRDS("MTBLS79.rds")
    } else {
      stop("Input file MTBLS79 or MTBLS79.rds not found in the working directory.")
    }
    
    # 2. Filter samples by missing value percentage
    MTBLS79_filtered <- filter_samples_by_mv(df=MTBLS79, max_perc_mv=0.1)
    
    # 3. Filter peaks by fraction of missing values in QC samples
    MTBLS79_filtered <- filter_peaks_by_fraction(df=MTBLS79_filtered, min_frac=0.9, classes=MTBLS79_filtered\$Class, method="QC", qc_label="QC")
    
    # 4. Filter peaks by fraction of missing values across all samples
    MTBLS79_filtered <- filter_peaks_by_fraction(df=MTBLS79_filtered, min_frac=0.9, classes=MTBLS79_filtered\$Class, method="across")
    
    # 5. Filter peaks by relative standard deviation (RSD) in QC samples
    MTBLS79_filtered <- filter_peaks_by_rsd(df=MTBLS79_filtered, max_rsd=30, classes=MTBLS79_filtered\$Class, qc_label="QC")
    
    # 6. Track processing history
    history_filtered <- processing_history(MTBLS79_filtered)
    sink("processing_history_filtered.txt")
    print(history_filtered)
    sink()
    
    # 7. Normalize data using probabilistic quotient normalization
    MTBLS79_pqn_normalised <- pqn_normalisation(df=MTBLS79_filtered, classes=MTBLS79_filtered\$Class, qc_label="QC")
    
    # 8. Impute missing values
    MTBLS79_mv_imputed <- mv_imputation(df=MTBLS79_pqn_normalised, method="knn")
    
    # 9. Perform generalized logarithm transformation
    MTBLS79_glog <- glog_transformation(df=MTBLS79_mv_imputed, classes=MTBLS79_filtered\$Class, qc_label="QC")
    
    # 10. Plot optimized lambda for glog transformation
    opt_lambda <- processing_history(MTBLS79_glog)\$glog_transformation\$lambda_opt
    
    pdf("glog_optimised_lambda_plot.pdf", width=7, height=5)
    glog_plot_optimised_lambda(df=MTBLS79_mv_imputed, optimised_lambda=opt_lambda, classes=MTBLS79_filtered\$Class, qc_label="QC")
    dev.off()
    
    # Save outputs
    saveRDS(MTBLS79_filtered, "MTBLS79_filtered.rds")
    saveRDS(MTBLS79_pqn_normalised, "MTBLS79_pqn_normalised.rds")
    saveRDS(MTBLS79_mv_imputed, "MTBLS79_mv_imputed.rds")
    saveRDS(MTBLS79_glog, "MTBLS79_glog.rds")
    
    # Export final processed peak matrix as CSV
    final_matrix <- assay(MTBLS79_glog)
    write.csv(final_matrix, "MTBLS79_processed_matrix.csv", row.names=TRUE)
    
    # Export sample metadata as CSV
    metadata <- as.data.frame(colData(MTBLS79_glog))
    write.csv(metadata, "MTBLS79_processed_metadata.csv", row.names=TRUE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_PMP_METABOLOMICS_FILTERING_AND_NORMALIZATION":',
        paste0('    pmp: ', as.character(packageVersion('pmp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabolomics_filtering_and_normalization.csv versions.yml
    """
}

workflow BIOC_PMP_METABOLOMICS_FILTERING_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MTBLS79 ] ]

    main:
    BIOC_PMP_METABOLOMICS_FILTERING_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_PMP_METABOLOMICS_FILTERING_AND_NORMALIZATION.out.tables
    plots    = BIOC_PMP_METABOLOMICS_FILTERING_AND_NORMALIZATION.out.plots
    objects  = BIOC_PMP_METABOLOMICS_FILTERING_AND_NORMALIZATION.out.objects
    versions = BIOC_PMP_METABOLOMICS_FILTERING_AND_NORMALIZATION.out.versions
}
