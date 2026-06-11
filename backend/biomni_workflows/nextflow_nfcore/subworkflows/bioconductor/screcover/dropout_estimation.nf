#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scRecover — dropout_estimation
// Estimate the dropout gene number or total expressed gene number in a single cell using downsampling.
// Input: oneCell
// Container: quay.io/biocontainers/bioconductor-screcover:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: scRecover
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Downsample read counts using countsSampling
//  * 2. [Core Analysis] Estimate the dropout gene number using estDropoutNum

nextflow.enable.dsl = 2

process BIOC_SCRECOVER_DROPOUT_ESTIMATION {
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
        library(scRecover)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input
        # -----------------------------------------------------------------------------
        # The pipeline expects 'oneCell' in the working directory as an RDS, CSV, or TXT file.
        oneCell <- NULL
        
        if (file.exists("oneCell.rds")) {
          oneCell <- readRDS("oneCell.rds")
        } else if (file.exists("oneCell.csv")) {
          df <- read.csv("oneCell.csv", header = TRUE, stringsAsFactors = FALSE)
          if (ncol(df) >= 2) {
            oneCell <- as.numeric(df[[2]])
            names(oneCell) <- df[[1]]
          } else {
            oneCell <- as.numeric(df[[1]])
            names(oneCell) <- rownames(df)
          }
        } else if (file.exists("oneCell.txt")) {
          df <- read.table("oneCell.txt", header = TRUE, stringsAsFactors = FALSE)
          if (ncol(df) >= 2) {
            oneCell <- as.numeric(df[[2]])
            names(oneCell) <- df[[1]]
          } else {
            oneCell <- as.numeric(df[[1]])
            names(oneCell) <- rownames(df)
          }
        } else {
          stop("Error: Input file 'oneCell' (as .rds, .csv, or .txt) not found in the working directory.")
        }
        
        # Ensure the input is a numeric vector while preserving gene names
        orig_names <- names(oneCell)
        oneCell <- as.numeric(oneCell)
        names(oneCell) <- orig_names
        
        if (is.null(names(oneCell))) {
          names(oneCell) <- paste0("Gene_", seq_along(oneCell))
        }
        
        # -----------------------------------------------------------------------------
        # 2. Downsample Read Counts
        # -----------------------------------------------------------------------------
        # Downsample 10% read counts in oneCell
        set.seed(999)
        oneCell.down <- countsSampling(counts = oneCell, fraction = 0.1)
        
        # -----------------------------------------------------------------------------
        # 3. Count Groundtruth Dropout Genes
        # -----------------------------------------------------------------------------
        # Count the groundtruth dropout gene number in the downsampled cell
        groundtruth_dropout <- sum(oneCell.down == 0 & oneCell != 0)
        
        # -----------------------------------------------------------------------------
        # 4. Estimate Dropout Gene Number
        # -----------------------------------------------------------------------------
        # Estimate the dropout gene number in the downsampled cell by estDropoutNum
        estimated_dropout <- estDropoutNum(sample = oneCell.down, depth = 10, return = "dropoutNum")
        
        # -----------------------------------------------------------------------------
        # 5. Save Outputs
        # -----------------------------------------------------------------------------
        # Save the downsampled counts
        downsampled_df <- data.frame(
          Gene = names(oneCell),
          Original_Count = oneCell,
          Downsampled_Count = oneCell.down,
          stringsAsFactors = FALSE
        )
        write.csv(downsampled_df, "oneCell_downsampled.csv", row.names = FALSE)
        saveRDS(oneCell.down, "oneCell_downsampled.rds")
        
        # Save the estimation summary
        summary_df <- data.frame(
          Metric = c("Groundtruth_Dropout_Genes", "Estimated_Dropout_Genes"),
          Value = c(groundtruth_dropout, estimated_dropout),
          stringsAsFactors = FALSE
        )
        write.csv(summary_df, "dropout_estimation_results.csv", row.names = FALSE)
        
        cat("Pipeline completed successfully.\n")
        cat("Groundtruth dropout genes:", groundtruth_dropout, "\n")
        cat("Estimated dropout genes:", estimated_dropout, "\n")

    writeLines(c(
        '"BIOC_SCRECOVER_DROPOUT_ESTIMATION":',
        paste0('    scRecover: ', as.character(packageVersion('scRecover')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dropout_estimation.csv versions.yml
    """
}

workflow BIOC_SCRECOVER_DROPOUT_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ oneCell ] ]

    main:
    BIOC_SCRECOVER_DROPOUT_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_SCRECOVER_DROPOUT_ESTIMATION.out.tables
    plots    = BIOC_SCRECOVER_DROPOUT_ESTIMATION.out.plots
    objects  = BIOC_SCRECOVER_DROPOUT_ESTIMATION.out.objects
    versions = BIOC_SCRECOVER_DROPOUT_ESTIMATION.out.versions
}
