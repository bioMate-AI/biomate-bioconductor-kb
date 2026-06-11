#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rgsepd — gsepd_analysis_pipeline
// Run the complete rgsepd pipeline to perform differential expression, GO enrichment, and multidimensional projection display analysis.
// Input: finalCounts, sampleMeta
// Container: quay.io/biocontainers/bioconductor-rgsepd:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: rgsepd
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files from Working Directory
//  * 2. [Visualization & Output] Standardize and Clean Metadata to Prevent Common Pitfalls
//  * 3. [Visualization & Output] Execute rgsepd Pipeline

nextflow.enable.dsl = 2

process BIOC_RGSEPD_GSEPD_ANALYSIS_PIPELINE {
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
        if (!requireNamespace("rgsepd", quietly = TRUE)) {
          stop("Package 'rgsepd' is required but not installed.")
        }
        library(rgsepd)
        
        # ----------------------------------------------------------------------
        # --- Read User Input Files from Working Directory ---
        # ----------------------------------------------------------------------
        
        # Locate finalCounts file
        fc_path <- "finalCounts"
        if (!file.exists(fc_path)) {
          for (ext in c(".csv", ".tsv", ".txt")) {
            if (file.exists(paste0("finalCounts", ext))) {
              fc_path <- paste0("finalCounts", ext)
              break
            }
          }
        }
        if (!file.exists(fc_path)) {
          stop("Error: 'finalCounts' file not found in the working directory.")
        }
        
        # Read finalCounts matrix
        finalCounts_df <- read.csv(fc_path, row.names = 1, check.names = FALSE)
        if (ncol(finalCounts_df) == 0) {
          finalCounts_df <- read.table(fc_path, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        }
        finalCounts_mat <- as.matrix(finalCounts_df)
        
        # Locate sampleMeta file
        sm_path <- "sampleMeta"
        if (!file.exists(sm_path)) {
          for (ext in c(".csv", ".tsv", ".txt")) {
            if (file.exists(paste0("sampleMeta", ext))) {
              sm_path <- paste0("sampleMeta", ext)
              break
            }
          }
        }
        if (!file.exists(sm_path)) {
          stop("Error: 'sampleMeta' file not found in the working directory.")
        }
        
        # Read sampleMeta data frame
        sampleMeta_df <- read.csv(sm_path, check.names = FALSE)
        if (ncol(sampleMeta_df) <= 1) {
          sampleMeta_df <- read.table(sm_path, header = TRUE, sep = "\t", check.names = FALSE)
        }
        
        # ----------------------------------------------------------------------
        # --- Standardize and Clean Metadata to Prevent Common Pitfalls ---
        # ----------------------------------------------------------------------
        
        cols <- colnames(sampleMeta_df)
        sample_idx <- grep("sample", cols, ignore.case = TRUE)[1]
        cond_idx <- grep("condition", cols, ignore.case = TRUE)[1]
        short_idx <- grep("short|nick|name", cols, ignore.case = TRUE)[1]
        
        if (is.na(sample_idx)) sample_idx <- 1
        if (is.na(cond_idx)) cond_idx <- 2
        if (is.na(short_idx)) short_idx <- 3
        
        clean_meta <- data.frame(
          Sample = as.character(sampleMeta_df[[sample_idx]]),
          Condition = as.character(sampleMeta_df[[cond_idx]]),
          SHORTNAME = as.character(sampleMeta_df[[short_idx]]),
          stringsAsFactors = FALSE
        )
        
        # Resolve potential R column name conversion mismatches (e.g. spaces to dots)
        matched_samples <- sapply(clean_meta\$Sample, function(s) {
          if (s %in% colnames(finalCounts_mat)) return(s)
          ms <- make.names(s)
          if (ms %in% colnames(finalCounts_mat)) return(ms)
          return(s)
        })
        clean_meta\$Sample <- matched_samples
        
        # Ensure condition names do not contain spaces
        clean_meta\$Condition <- gsub(" ", "_", clean_meta\$Condition)
        
        # ----------------------------------------------------------------------
        # --- Execute rgsepd Pipeline ---
        # ----------------------------------------------------------------------
        
        # Map gene symbols of interest to RefSeq IDs
        isoform_ids <- Name_to_RefSeq(c("GAPDH", "HIF1A", "EGFR", "MYH7", "CD33", "BRCA2"))
        
        # Initialize the GSEPD object
        G <- GSEPD_INIT(Output_Folder = "OUT",
                        finalCounts = round(finalCounts_mat),
                        sampleMeta = clean_meta,
                        COLORS = c(blue = "#4DA3FF", black = "#000000", gold = "#FFFF4D"))
        
        # Define comparison conditions dynamically based on metadata
        target_conditions <- c("A", "B")
        if (!all(target_conditions %in% clean_meta\$Condition)) {
          target_conditions <- unique(clean_meta\$Condition)[1:2]
        }
        
        # Adjust delimiter if condition names contain the letter 'x' to avoid parsing errors
        if (any(grepl("x", target_conditions, ignore.case = TRUE))) {
          G\$C2T_Delimiter <- 'z'
        }
        
        G <- GSEPD_ChangeConditions(G, target_conditions)
        
        # Customize pipeline parameters
        G\$MAX_Genes_for_Heatmap <- 30
        G\$MAX_GOs_for_Heatmap <- 25
        G\$MaxGenesInSet <- 12
        G\$LIMIT\$LFC <- log(2.50, 2)
        G\$LIMIT\$HARD <- FALSE
        
        # Execute the automated pipeline
        G <- GSEPD_Process(G)
        
        # Generate visualizations
        print(isoform_ids)
        tryCatch({
          GSEPD_Heatmap(G, isoform_ids)
        }, error = function(e) {
          warning("GSEPD_Heatmap failed: ", e\$message)
        })
        
        tryCatch({
          GSEPD_PCA_Plot(G)
        }, error = function(e) {
          warning("GSEPD_PCA_Plot failed: ", e\$message)
        })
        
        # Save the final processed GSEPD object
        saveRDS(G, file = "OUT/GSEPD_final_object.rds")

    writeLines(c(
        '"BIOC_RGSEPD_GSEPD_ANALYSIS_PIPELINE":',
        paste0('    rgsepd: ', as.character(packageVersion('rgsepd')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsepd_analysis_pipeline.csv versions.yml
    """
}

workflow BIOC_RGSEPD_GSEPD_ANALYSIS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ finalCounts, sampleMeta ] ]

    main:
    BIOC_RGSEPD_GSEPD_ANALYSIS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RGSEPD_GSEPD_ANALYSIS_PIPELINE.out.tables
    plots    = BIOC_RGSEPD_GSEPD_ANALYSIS_PIPELINE.out.plots
    objects  = BIOC_RGSEPD_GSEPD_ANALYSIS_PIPELINE.out.objects
    versions = BIOC_RGSEPD_GSEPD_ANALYSIS_PIPELINE.out.versions
}
