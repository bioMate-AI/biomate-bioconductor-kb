#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MsFeatures — stepwise_feature_grouping
// Group mass spectrometry features stepwise based on retention time similarity and refine them using abundance correlation across samples.
// Input: SummarizedExperiment
// Container: quay.io/biocontainers/bioconductor-msfeatures:1.18.0--r45hdfd78af_0
// R packages: MsFeatures, pheatmap, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: MsFeatures, SummarizedExperiment, pheatmap
// Visualizations: heatmap, image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Group features by similar retention times using groupFeatures and SimilarRtimeParam
//  * 2. [Core Analysis] Refine the retention time-based groups by abundance correlation using groupFeatures and AbundanceSimilarityParam

nextflow.enable.dsl = 2

process BIOC_MSFEATURES_STEPWISE_FEATURE_GROUPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("MsFeatures", "pheatmap", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(MsFeatures)
    
    library(SummarizedExperiment)
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects a SummarizedExperiment object saved as an RDS file
    # in the working directory (either "se.rds" or "SummarizedExperiment.rds").
    input_file <- NULL
    possible_files <- c("se.rds", "SummarizedExperiment.rds")
    for (f in possible_files) {
      if (file.exists(f)) {
        input_file <- f
        break
      }
    }
    
    if (is.null(input_file)) {
      stop("Error: Input SummarizedExperiment file ('se.rds' or 'SummarizedExperiment.rds') not found in the working directory.")
    }
    
    message("Reading input file: ", input_file)
    se <- readRDS(input_file)
    
    # Validate that the object is a SummarizedExperiment and contains the required columns
    if (!is(se, "SummarizedExperiment")) {
      stop("Error: The input file does not contain a SummarizedExperiment object.")
    }
    if (!"rtmed" %in% colnames(rowData(se))) {
      stop("Error: The rowData of the SummarizedExperiment must contain a 'rtmed' column for retention times.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Stepwise Feature Grouping Workflow
    # -----------------------------------------------------------------------------
    
    # Stage 1: Group features by similar retention times
    message("Grouping features by similar retention times (SimilarRtimeParam)...")
    se <- groupFeatures(se, param = SimilarRtimeParam(10), rtime = "rtmed")
    
    # Stage 2: Refine the retention time-based groups by abundance correlation
    message("Refining feature groups by abundance correlation (AbundanceSimilarityParam)...")
    se <- groupFeatures(se, AbundanceSimilarityParam(threshold = 0.7,
                                                     transform = log2), i = 1)
    
    # -----------------------------------------------------------------------------
    # 3. Generate Outputs
    # -----------------------------------------------------------------------------
    
    # Output 1: Save the final grouped SummarizedExperiment object
    output_rds <- "grouped_se.rds"
    message("Saving grouped SummarizedExperiment to: ", output_rds)
    saveRDS(se, output_rds)
    
    # Output 2: Save the feature metadata with group assignments as a CSV table
    output_csv <- "grouped_features_metadata.csv"
    message("Saving feature metadata and group assignments to: ", output_csv)
    write.csv(as.data.frame(rowData(se)), file = output_csv, row.names = TRUE)
    
    # Output 3: Generate diagnostic plots and save to a PDF
    output_pdf <- "feature_grouping_plots.pdf"
    message("Generating diagnostic plots in: ", output_pdf)
    pdf(output_pdf, width = 10, height = 10)
    
    # Plot 1: Retention time vs m/z of all features
    if ("mzmed" %in% colnames(rowData(se))) {
      plot(rowData(se)\$rtmed, rowData(se)\$mzmed,
           xlab = "Retention Time (rtmed)", ylab = "m/z (mzmed)", 
           main = "MS Features: Retention Time vs m/z",
           col = "#00000060", pch = 19)
      grid()
    } else {
      plot(rowData(se)\$rtmed, seq_len(nrow(se)),
           xlab = "Retention Time (rtmed)", ylab = "Feature Index",
           main = "MS Features: Retention Time",
           col = "#00000060", pch = 19)
      grid()
    }
    
    # Plot 2: Correlation Heatmap of Feature Abundances (using pheatmap if available, otherwise base image)
    fvals <- log2(assay(se, 1))
    cormat <- cor(t(fvals), use = "pairwise.complete.obs")
    
    if (requireNamespace("pheatmap", quietly = TRUE)) {
      ann <- data.frame(fgroup = featureGroups(se))
      rownames(ann) <- rownames(cormat)
      pheatmap::pheatmap(cormat, 
                         annotation_row = ann, 
                         cluster_rows = TRUE,
                         cluster_cols = TRUE,
                         show_rownames = FALSE,
                         show_colnames = FALSE,
                         main = "Correlation of Features Based on Abundances")
    } else {
      image(cormat, main = "Correlation Matrix of Feature Abundances (Base Image)",
            col = hcl.colors(12, "YlOrRd", rev = TRUE))
    }
    
    # Plot 3: Pairwise correlation plots for the first non-trivial feature group
    fg_counts <- table(featureGroups(se))
    multi_feat_groups <- names(fg_counts[fg_counts > 1 & fg_counts < 10])
    
    if (length(multi_feat_groups) > 0) {
      target_group <- multi_feat_groups[1]
      fts <- which(featureGroups(se) == target_group)
      if (length(fts) >= 2) {
        pairs(t(fvals[fts, , drop = FALSE]), gap = 0.1, 
              main = paste("Pairwise Correlation for Group:", target_group))
      }
    }
    
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MSFEATURES_STEPWISE_FEATURE_GROUPING":',
        paste0('    MsFeatures: ', as.character(packageVersion('MsFeatures')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stepwise_feature_grouping.csv versions.yml
    """
}

workflow BIOC_MSFEATURES_STEPWISE_FEATURE_GROUPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment ] ]

    main:
    BIOC_MSFEATURES_STEPWISE_FEATURE_GROUPING(ch_input)

    emit:
    tables   = BIOC_MSFEATURES_STEPWISE_FEATURE_GROUPING.out.tables
    plots    = BIOC_MSFEATURES_STEPWISE_FEATURE_GROUPING.out.plots
    objects  = BIOC_MSFEATURES_STEPWISE_FEATURE_GROUPING.out.objects
    versions = BIOC_MSFEATURES_STEPWISE_FEATURE_GROUPING.out.versions
}
