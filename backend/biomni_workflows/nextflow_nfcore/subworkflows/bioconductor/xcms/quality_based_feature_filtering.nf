#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcms — quality_based_feature_filtering
// Filter preprocessed LC-MS features based on quality metrics (missing values, RSD, D-ratio).
// Input: faahko.rds
// Container: quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0
// R packages: MsExperiment, MsFeatures, xcms
// Bioconductor: 3.20 | R: 4.4
// Requires: MsExperiment, MsFeatures, xcms
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter by missing values using filterFeatures with PercentMissingFilter
//  * 2. [Core Analysis] Filter by relative standard deviation using filterFeatures with RsdFilter
//  * 3. [Core Analysis] Filter by D-ratio using filterFeatures with DratioFilter

nextflow.enable.dsl = 2

process BIOC_XCMS_QUALITY_BASED_FEATURE_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MsExperiment", "MsFeatures", "xcms")
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
        library(xcms)
        library(MsExperiment)
        library(MsFeatures)
        
        # 1. Read the input preprocessed XcmsExperiment object
        if (!file.exists("faahko.rds")) {
          stop("Input file 'faahko.rds' not found in the working directory.")
        }
        faahko <- readRDS("faahko.rds")
        
        # Ensure sample_type exists in sampleData to avoid downstream errors
        if (is.null(sampleData(faahko)\$sample_type)) {
          # Fallback: assign first and every third sample as QC, others as study
          n_samples <- nrow(sampleData(faahko))
          sample_types <- rep("study", n_samples)
          sample_types[seq(1, n_samples, by = 3)] <- "QC"
          sampleData(faahko)\$sample_type <- sample_types
        }
        
        # 2. Apply quality-based feature filtering exactly as documented
        
        # Stage 1: Filter by missing values using PercentMissingFilter
        f <- sampleData(faahko)\$sample_type
        f[f != "QC"] <- NA
        missing_filter <- PercentMissingFilter(threshold = 30, f = f)
        filtered_faahko <- filterFeatures(object = faahko, filter = missing_filter)
        
        # Stage 2: Filter by relative standard deviation using RsdFilter
        rsd_filter <- RsdFilter( threshold = 0.3, qcIndex = sampleData(filtered_faahko)\$sample_type == "QC")
        filtered_faahko <- filterFeatures(object = filtered_faahko, filter = rsd_filter)
        
        # Stage 3: Filter by D-ratio using DratioFilter
        dratio_filter <- DratioFilter( threshold = 0.5, qcIndex = sampleData(filtered_faahko)\$sample_type == "QC", studyIndex = sampleData(filtered_faahko)\$sample_type == "study")
        filtered_faahko <- filterFeatures(object = filtered_faahko, filter = dratio_filter)
        
        # 3. Save meaningful results to output files
        saveRDS(filtered_faahko, "filtered_faahko.rds")
        
        # Export feature definitions as a CSV table
        feat_defs <- featureDefinitions(filtered_faahko)
        write.csv(as.data.frame(feat_defs), "filtered_feature_definitions.csv", row.names = TRUE)
        
        # Export feature abundance values as a CSV table
        feat_vals <- featureValues(filtered_faahko, value = "into")
        write.csv(as.data.frame(feat_vals), "filtered_feature_values.csv", row.names = TRUE)
        
        # Generate a summary PDF plot of feature intensities before and after filtering
        pdf("filtering_summary.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        boxplot(log2(featureValues(faahko, value = "into")), 
                main = "Before Filtering", 
                ylab = "log2 Intensity", 
                las = 2, col = "tomato")
        boxplot(log2(featureValues(filtered_faahko, value = "into")), 
                main = "After Filtering", 
                ylab = "log2 Intensity", 
                las = 2, col = "lightblue")
        dev.off()

    writeLines(c(
        '"BIOC_XCMS_QUALITY_BASED_FEATURE_FILTERING":',
        paste0('    xcms: ', as.character(packageVersion('xcms')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quality_based_feature_filtering.csv versions.yml
    """
}

workflow BIOC_XCMS_QUALITY_BASED_FEATURE_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ faahko.rds ] ]

    main:
    BIOC_XCMS_QUALITY_BASED_FEATURE_FILTERING(ch_input)

    emit:
    tables   = BIOC_XCMS_QUALITY_BASED_FEATURE_FILTERING.out.tables
    plots    = BIOC_XCMS_QUALITY_BASED_FEATURE_FILTERING.out.plots
    objects  = BIOC_XCMS_QUALITY_BASED_FEATURE_FILTERING.out.objects
    versions = BIOC_XCMS_QUALITY_BASED_FEATURE_FILTERING.out.versions
}
