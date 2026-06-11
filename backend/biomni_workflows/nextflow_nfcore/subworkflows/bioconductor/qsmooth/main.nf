#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qsmooth — smooth_quantile_normalization
// Perform smooth quantile normalization on high-throughput expression data using biological group covariates, and visualize the calculated weights.
// Input: counts1, pd1$organ
// Container: quay.io/biocontainers/bioconductor-qsmooth:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: qsmooth
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run qsmooth to compute weights and normalize the data. 2. Extract the normalized expression matrix using qsmoothData. 3. Plot the 

nextflow.enable.dsl = 2

process BIOC_QSMOOTH_SMOOTH_QUANTILE_NORMALIZATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(qsmooth)
    
    # Read user input files from the working directory
    # counts1: matrix or data frame of raw expression counts (genes in rows, samples in columns)
    if (file.exists("counts1.csv")) {
      counts1 <- as.matrix(read.csv("counts1.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("counts1.tsv")) {
      counts1 <- as.matrix(read.delim("counts1.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: counts1.csv or counts1.tsv not found in the working directory.")
    }
    
    # pd1: sample metadata containing the 'organ' column representing the biological group
    if (file.exists("pd1.csv")) {
      pd1 <- read.csv("pd1.csv", stringsAsFactors = FALSE)
    } else if (file.exists("pd1.tsv")) {
      pd1 <- read.delim("pd1.tsv", stringsAsFactors = FALSE)
    } else {
      stop("Error: pd1.csv or pd1.tsv not found in the working directory.")
    }
    
    # Validate inputs
    if (!"organ" %in% colnames(pd1)) {
      stop("Error: The metadata must contain an 'organ' column representing the biological group.")
    }
    
    # 1. Run qsmooth to compute weights and normalize the data
    qs_norm_e1 <- qsmooth(object = counts1, group_factor = pd1\$organ)
    
    # 2. Extract the normalized expression matrix using qsmoothData
    normalized_matrix <- qsmoothData(qs_norm_e1)
    
    # Save the normalized expression matrix to a CSV file
    write.csv(normalized_matrix, "normalized_counts.csv", row.names = TRUE)
    
    # Save the full qsmooth object as an RDS file for downstream analysis
    saveRDS(qs_norm_e1, "qs_norm_e1.rds")
    
    # 3. Plot the computed weights across quantiles using qsmoothPlotWeights and save as PDF
    pdf("qsmooth_weights.pdf", width = 7, height = 5)
    qsmoothPlotWeights(qs_norm_e1)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: normalized_counts.csv, qs_norm_e1.rds, qsmooth_weights.pdf\n")

    writeLines(c(
        '"BIOC_QSMOOTH_SMOOTH_QUANTILE_NORMALIZATION":',
        paste0('    qsmooth: ', as.character(packageVersion('qsmooth')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_smooth_quantile_normalization.csv versions.yml
    """
}

workflow BIOC_QSMOOTH_SMOOTH_QUANTILE_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts1, pd1$organ ] ]

    main:
    BIOC_QSMOOTH_SMOOTH_QUANTILE_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_QSMOOTH_SMOOTH_QUANTILE_NORMALIZATION.out.tables
    plots    = BIOC_QSMOOTH_SMOOTH_QUANTILE_NORMALIZATION.out.plots
    objects  = BIOC_QSMOOTH_SMOOTH_QUANTILE_NORMALIZATION.out.objects
    versions = BIOC_QSMOOTH_SMOOTH_QUANTILE_NORMALIZATION.out.versions
}
