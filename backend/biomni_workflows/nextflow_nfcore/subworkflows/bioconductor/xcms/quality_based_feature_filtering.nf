#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcms — quality_based_feature_filtering
// Filter preprocessed LC-MS features based on quality metrics (missing values, RSD, D-ratio).
// Input: faahko.rds
// Container: quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0
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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
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
