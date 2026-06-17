#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TOAST — cell_type_specific_differential_analysis
// Detect cell-type specific and cross-cell type differential signals (csDE/csDM) from heterogeneous bulk high-throughput data using known or estimated cell propor
// Input: Y_raw, design, Prop
// Container: quay.io/biocontainers/bioconductor-toast:1.24.0--r45hdfd78af_0
// R packages: EpiDISH, TOAST
// Bioconductor: 3.20 | R: 4.4
// Requires: TOAST
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Robust Covariate & Cell Type Alignment
//  * 3. [Core Analysis] Execute Documented TOAST Workflow

nextflow.enable.dsl = 2

process BIOC_TOAST_CELL_TYPE_SPECIFIC_DIFFERENTIAL_ANALYSIS {
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
    .bm_deps <- c("EpiDISH", "TOAST")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        
        # Complete, runnable R pipeline for TOAST cell-type specific differential analysis.
        # This script reads user-provided bulk data, design covariates, and cell proportions,
        # and performs csDE/csDM analysis using the exact documented workflow.
        
        library(TOAST)
        
        # ==========================================
        # --- Read User Input Files ---
        # ==========================================
        
        read_input_file <- function(base_name) {
          extensions <- c(".rds", ".csv", ".tsv", ".txt", "")
          for (ext in extensions) {
            file_path <- paste0(base_name, ext)
            if (file.exists(file_path)) {
              message("Reading input file: ", file_path)
              if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
                return(readRDS(file_path))
              } else if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) {
                return(read.csv(file_path, row.names = 1, check.names = FALSE))
              } else if (grepl("\\\\.(tsv|txt)\$", file_path, ignore.case = TRUE)) {
                return(read.delim(file_path, row.names = 1, check.names = FALSE))
              } else {
                # Fallback attempts
                obj <- tryCatch(readRDS(file_path), error = function(e) NULL)
                if (!is.null(obj)) return(obj)
                obj <- tryCatch(read.csv(file_path, row.names = 1, check.names = FALSE), error = function(e) NULL)
                if (!is.null(obj)) return(obj)
              }
            }
          }
          stop(paste("Error: Could not find input file for", base_name))
        }
        
        # Load the required user inputs
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        Y_raw_input <- read_input_file("Y_raw")
        design_input <- read_input_file("design")
        Prop_input <- read_input_file("Prop")
        
        # Assign to standard variables
        Y_raw <- Y_raw_input
        Pheno <- as.data.frame(design_input)
        estProp_RF_improved <- as.matrix(Prop_input)
        
        # ==========================================
        # --- Robust Covariate & Cell Type Alignment ---
        # ==========================================
        
        # Convert character and binary numeric columns in Pheno to factors
        for (col in colnames(Pheno)) {
          if (is.character(Pheno[[col]])) {
            Pheno[[col]] <- as.factor(Pheno[[col]])
          } else if (is.numeric(Pheno[[col]]) && length(unique(na.omit(Pheno[[col]]))) == 2) {
            Pheno[[col]] <- as.factor(Pheno[[col]])
          }
        }
        
        # Ensure the proportion matrix has column names
        if (is.null(colnames(estProp_RF_improved))) {
          colnames(estProp_RF_improved) <- paste0("CellType_", seq_len(ncol(estProp_RF_improved)))
        } else {
          for (i in 1:ncol(estProp_RF_improved)) {
            if (is.na(colnames(estProp_RF_improved)[i]) || colnames(estProp_RF_improved)[i] == "") {
              colnames(estProp_RF_improved)[i] <- paste0("CellType_", i)
            }
          }
        }
        
        # Define Ref to match the documented code's column assignment step
        Ref <- estProp_RF_improved
        
        # ==========================================
        # --- Execute Documented TOAST Workflow ---
        # ==========================================
        
        design <- Pheno
        
        Prop <- estProp_RF_improved
        colnames(Prop) <- colnames(Ref) 
        Design_out <- makeDesign(design, Prop)
        fitted_model <- fitModel(Design_out, Y_raw)
        
        cell_types <- fitted_model\$all_cell_types
        coefs <- fitted_model\$all_coefs
        coefs <- coefs[coefs != "(Intercept)"]
        
        if (length(coefs) > 0 && length(cell_types) > 0) {
          c1 <- coefs[1]
          ct1 <- cell_types[1]
          
          # Test first covariate effect in first cell type
          res_table <- csTest(fitted_model, coef = c1, cell_type = ct1)
          head(res_table, 3)
          write.csv(res_table, paste0("res_table_", c1, "_", ct1, ".csv"), row.names = TRUE)
          
          # Test joint first covariate effect
          res_table <- csTest(fitted_model, coef = c1, cell_type = "joint")
          write.csv(res_table, paste0("res_table_", c1, "_joint.csv"), row.names = TRUE)
          
          # Test first covariate effect in all cell types individually and jointly
          res_table <- csTest(fitted_model, coef = c1, cell_type = NULL)
          if (is.list(res_table) && !is.data.frame(res_table)) {
            for (name in names(res_table)) {
              write.csv(res_table[[name]], paste0("res_table_", c1, "_all_", name, ".csv"), row.names = TRUE)
            }
          } else {
            write.csv(res_table, paste0("res_table_", c1, "_all.csv"), row.names = TRUE)
          }
        }
        
        if (length(coefs) > 1 && length(cell_types) > 1) {
          c2 <- coefs[2]
          ct2 <- cell_types[2]
          
          # Test second covariate effect in second cell type
          if (is.factor(design[[c2]]) && length(levels(design[[c2]])) >= 2) {
            lvl1 <- levels(design[[c2]])[1]
            lvl2 <- levels(design[[c2]])[2]
            res_table <- csTest(fitted_model, coef = c(c2, lvl2, lvl1), cell_type = ct2)
            write.csv(res_table, paste0("res_table_", c2, "_", lvl2, "_vs_", lvl1, "_", ct2, ".csv"), row.names = TRUE)
          } else {
            res_table <- csTest(fitted_model, coef = c2, cell_type = ct2)
            write.csv(res_table, paste0("res_table_", c2, "_", ct2, ".csv"), row.names = TRUE)
          }
        }
        
        if (length(coefs) > 0 && length(cell_types) >= 2) {
          c1 <- coefs[1]
          ct1 <- cell_types[1]
          ct2 <- cell_types[2]
          
          # Test cross-cell type differences in first covariate group
          if (is.factor(design[[c1]]) && length(levels(design[[c1]])) >= 1) {
            lvl1 <- levels(design[[c1]])[1]
            test <- csTest(fitted_model, coef = c(c1, lvl1), cell_type = c(ct1, ct2), contrast_matrix = NULL)
            write.csv(test, paste0("test_", c1, "_", lvl1, "_", ct1, "_", ct2, ".csv"), row.names = TRUE)
          } else {
            test <- csTest(fitted_model, coef = c1, cell_type = c(ct1, ct2), contrast_matrix = NULL)
            write.csv(test, paste0("test_", c1, "_", ct1, "_", ct2, ".csv"), row.names = TRUE)
          }
        }
        
        if (length(cell_types) >= 2) {
          ct1 <- cell_types[1]
          ct2 <- cell_types[2]
          
          # Test overall cross-cell type differences
          test <- csTest(fitted_model, coef = "joint", cell_type = c(ct1, ct2), contrast_matrix = NULL)
          write.csv(test, paste0("test_joint_", ct1, "_", ct2, ".csv"), row.names = TRUE)
        }
        
        # Save the fitted model object
        saveRDS(fitted_model, "fitted_model.rds")
        
        message("TOAST pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_TOAST_CELL_TYPE_SPECIFIC_DIFFERENTIAL_ANALYSIS":',
        paste0('    TOAST: ', as.character(packageVersion('TOAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_type_specific_differential_analysis.csv versions.yml
    """
}

workflow BIOC_TOAST_CELL_TYPE_SPECIFIC_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y_raw, design, Prop ] ]

    main:
    BIOC_TOAST_CELL_TYPE_SPECIFIC_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TOAST_CELL_TYPE_SPECIFIC_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_TOAST_CELL_TYPE_SPECIFIC_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_TOAST_CELL_TYPE_SPECIFIC_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_TOAST_CELL_TYPE_SPECIFIC_DIFFERENTIAL_ANALYSIS.out.versions
}
