#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scp — scp_single_cell_proteomics_pipeline
// Perform a complete multi-stage single-cell proteomics analysis including data loading, quality control, feature aggregation, normalization, and missing value/se
// Input: counts.csv, coldata.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MsCoreUtils, QFeatures, ggplot2, scp
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCP_SCP_SINGLE_CELL_PROTEOMICS_PIPELINE {
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
    library(scp)
    library(QFeatures)
    library(ggplot2)
    
    # ==========================================
    # STAGE 1: Data Loading and Object Creation
    # ==========================================
    
    # Read input files
    counts <- read.csv("counts.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Ensure sample names are characters and set as row names for colData
    rownames(coldata) <- coldata\$sample
    
    # Prepare colData with required columns for readSCP:
    # - runCol: defines the MS run/batch
    # - quantCols: defines the columns in assayData containing quantitative values
    coldata\$runCol <- "run1"
    coldata\$quantCols <- coldata\$sample
    
    # Prepare assayData (counts) with matching run column
    counts\$Raw.file <- "run1"
    
    # Create the QFeatures object using readSCP
    scp_obj <- readSCP(
      assayData = counts,
      colData = coldata,
      runCol = "Raw.file",
      removeEmptyCols = TRUE
    )
    
    # ==========================================
    # STAGE 2: Quality Control & Filtering
    # ==========================================
    
    # Convert zero values to NA (standard practice in mass spectrometry proteomics)
    scp_obj <- zeroIsNA(scp_obj, i = names(scp_obj))
    
    # Filter out features with excessive missingness (keep features with < 99% missing values)
    scp_obj <- filterNA(scp_obj, i = names(scp_obj), pNA = 0.99)
    
    # ==========================================
    # STAGE 3: Feature Aggregation
    # ==========================================
    
    # To demonstrate aggregation from peptide/PSM level to protein level,
    # we group features into mock proteins (grouping every 3 features)
    first_assay_name <- names(scp_obj)[1]
    n_rows <- nrow(scp_obj[[first_assay_name]])
    mock_proteins <- paste0("Prot_", rep(1:ceiling(n_rows / 3), each = 3)[1:n_rows])
    rowData(scp_obj[[first_assay_name]])\$protein <- mock_proteins
    
    # Aggregate features to protein level using robust summary
    scp_obj <- aggregateFeatures(
      scp_obj,
      i = first_assay_name,
      fcol = "protein",
      name = "proteins",
      fun = MsCoreUtils::robustSummary
    )
    
    # ==========================================
    # STAGE 4: Normalization & Log Transformation
    # ==========================================
    
    # Median-center the protein-level assay
    scp_obj <- normalize(
      scp_obj,
      i = "proteins",
      method = "center.median",
      name = "proteins_norm"
    )
    
    # Log2 transform the normalized data with a small pseudocount
    scp_obj <- logTransform(
      scp_obj,
      i = "proteins_norm",
      base = 2,
      pc = 1,
      name = "proteins_log"
    )
    
    # ==========================================
    # STAGE 5: Missing Value & Sensitivity Diagnostics
    # ==========================================
    
    # Report missing values grouped by experimental condition
    mv_report <- reportMissingValues(
      scp_obj,
      i = "proteins_log",
      by = scp_obj\$condition
    )
    write.csv(mv_report, "missing_value_report.csv", row.names = TRUE)
    
    # Compute Jaccard Index to assess identification consistency across cells
    ji <- tryCatch({
      jaccardIndex(scp_obj, "proteins_log", by = scp_obj\$condition)
    }, error = function(e) {
      warning("Jaccard index computation failed: ", e\$message)
      NULL
    })
    
    # Generate Cumulative Sensitivity Curve
    csc <- tryCatch({
      cumulativeSensitivityCurve(
        scp_obj,
        i = "proteins_log",
        by = scp_obj\$condition,
        batch = scp_obj\$runCol,
        niters = 5,
        nsteps = 10
      )
    }, error = function(e) {
      warning("Cumulative sensitivity curve computation failed: ", e\$message)
      NULL
    })
    
    # ==========================================
    # STAGE 6: Output Generation & Visualization
    # ==========================================
    
    # Save the final processed protein expression matrix
    processed_matrix <- assay(scp_obj, "proteins_log")
    write.csv(processed_matrix, "processed_proteins.csv", row.names = TRUE)
    
    # Plot diagnostics to PDF
    pdf("scp_diagnostics.pdf", width = 10, height = 5)
    
    # Plot 1: Jaccard Index Distribution
    if (!is.null(ji) && nrow(ji) > 0) {
      p1 <- ggplot(ji) +
        aes(x = jaccard) +
        geom_histogram(bins = 15, fill = "skyblue", color = "black") +
        facet_grid(~ by) +
        theme_minimal() +
        labs(
          title = "Jaccard Index Distribution by Condition",
          x = "Jaccard Index",
          y = "Count"
        )
      print(p1)
    }
    
    # Plot 2: Cumulative Sensitivity Curve
    if (!is.null(csc) && nrow(csc) > 0) {
      p2 <- ggplot(csc) +
        aes(x = SampleSize, y = Sensitivity, colour = by) +
        geom_point(size = 2) +
        geom_line() +
        theme_minimal() +
        labs(
          title = "Cumulative Sensitivity Curve",
          x = "Sample Size",
          y = "Sensitivity (Number of Proteins)"
        )
      print(p2)
    }
    
    dev.off()

    writeLines(c(
        '"BIOC_SCP_SCP_SINGLE_CELL_PROTEOMICS_PIPELINE":',
        paste0('    scp: ', as.character(packageVersion('scp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scp_single_cell_proteomics_pipeline.csv versions.yml
    """
}

workflow BIOC_SCP_SCP_SINGLE_CELL_PROTEOMICS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SCP_SCP_SINGLE_CELL_PROTEOMICS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_SCP_SCP_SINGLE_CELL_PROTEOMICS_PIPELINE.out.tables
    plots    = BIOC_SCP_SCP_SINGLE_CELL_PROTEOMICS_PIPELINE.out.plots
    objects  = BIOC_SCP_SCP_SINGLE_CELL_PROTEOMICS_PIPELINE.out.objects
    versions = BIOC_SCP_SCP_SINGLE_CELL_PROTEOMICS_PIPELINE.out.versions
}
